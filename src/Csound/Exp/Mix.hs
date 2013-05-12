module Csound.Exp.Mix(
    -- * Sound source
    InstrFun, 
    Instr(..), mkInstr,
    Arity(..), mkArity,
    
    -- * Mixer
    MixerNote(..), MixerExp(..),

    Effect, effect, effectS, 

    -- * Container for sounds (triggered with notes and mixers)
    Mix(..), M(..), nchnls,

    sco, mix --, midi, pgmidi
) where

import Control.Applicative
import Data.Traversable(traverse)

import Temporal.Music.Score(Score, temp, stretch, dur)

import Csound.Exp
import Csound.Exp.Wrapper
import Csound.Exp.SE
import Csound.Exp.GE
import Csound.Exp.Instr
import Csound.Exp.Arg
import Csound.Exp.Tuple(Out(..), CsdTuple, fromCsdTuple, toCsdTuple, outArity)
import qualified Csound.Render.IndexMap as DM

import Csound.Render.Channel(ins)

-- There are three types of instruments:
--
-- * sound sorces controlled by scores
-- * midi-instruments
-- * mix-instrument - listens to other instruments and applies effects.

-- Instrument is a sound source (controlled by score or midi). It has 
--
--  * name      - here we use stable names to distinguish instruments quickly
--  * arity     - how many arguments expected, how many signals to produce) 
--  * body      - actual Csound expression (it's a list of output signals, 
--                each signal is an expression-tree)

-- Mixer can expect sound from three sources:
data MixerNote 
    -- another mixer
    = MixerNote InstrId 
    -- instrument trigered by score
    | SoundNote InstrId (Score Note)

data MixerExp = MixerExp
    { mixerExpE   :: E
    , mixerExpSco :: Score MixerNote }

type Effect = [Sig] -> SE [Sig]

newtype Mix a = Mix { unMix :: GE M } 

data M 
    = Snd InstrId (Score Note)
    | Eff Instr (Score M)    

nchnls :: Out a => Score (Mix a) -> Int
nchnls = outArity . proxy  
    where proxy :: Score (Mix a) -> a
          proxy = undefined  

-- | Play a bunch of notes with the given instrument.
--
-- > res = sco instrument scores 
--
-- * @instrument@ is a function that takes notes and produces a 
--   tuple of signals (maybe with some side effect)
--  
-- * @scores@ are some notes (see the module "Temporal.Media" 
--   on how to build complex scores out of simple ones)
--
-- Let's try to understand the type of the output. It's @Score (Mix (NoSE a))@. 
-- What does it mean? Let's look at the different parts of this type:
--
-- * @Score a@ - you can think of it as a container of some values of 
--   type @a@ (every value of type @a@ starts at some time and lasts 
--   for some time in seconds)
--
-- * @Mix a@ - is an output of Csound instrument it can be one or several 
--   signals ('Csound.Base.Sig' or 'Csound.Base.CsdTuple'). 
--
-- *NoSE a* - it's a tricky part of the output. 'NoSE' means literaly 'no SE'. 
-- It tells to the type checker that it can skip the 'Csound.Base.SE' wrapper
-- from the type 'a' so that @SE a@ becomes just @a@ or @SE (a, SE b, c)@ 
-- becomes @(a, b, c)@. Why should it be? I need 'SE' to deduce the order of the
-- instruments that have side effects. I need it within one instrument. But when 
-- instrument is rendered i no longer need 'SE' type. So 'NoSE' lets me drop it
-- from the output type. 
sco :: (Arg a, Out b) => (a -> b) -> Score a -> Score (Mix (NoSE b))
sco instr notes = tempAs notes $ Mix $ fmap (flip Snd notes') $ saveInstr instr
    where notes' = fmap toNote notes

-- | Applies an effect to the sound. Effect is applied to the sound on the give track. 
--
-- > res = mix effect sco 
--
-- * @effect@ - a function that takes a tuple of signals and produces 
--   a tuple of signals.
--
-- * @sco@ - something that is constructed with 'Csound.Base.sco' or 
--   'Csound.Base.mix' or 'Csound.Base.midi'. 
--
-- With the function 'Csound.Base.mix' you can apply a reverb or adjust the 
-- level of the signal. It functions like a mixing board but unlike mixing 
-- board it produces the value that you can arrange with functions from the 
-- module "Temporal.Media". You can delay it mix with some other track and 
-- apply some another effect on top of it!
mix :: (Out a, Out b) => (a -> b) -> Score (Mix a) -> Score (Mix (NoSE b))
mix effect sigs = tempAs sigs $ Mix $ do
    notes <- traverse unMix sigs
    return $ Eff (Instr arity body) notes 
    where arity = mkArity outArity outArity effect
          body  = (toOut . effect . fromOut) =<< ins arity  

{-
-- | Triggers a midi-instrument (like Csound's massign). The result type 
-- is a fake one. It's wrapped in the 'Csound.Base.Score' for the ease of mixing.
-- you can not delay or stretch it. The only operation that is meaningful 
-- for it is 'Temporal.Media.chord'. But you can add effects to it with 'Csound.Base.mix'!
midi :: (Out a) => Channel -> (Msg -> a) -> Score (Mix (NoSE a))
midi = genMidi Massign

-- | Triggers a - midi-instrument (like Csound's pgmassign). 
pgmidi :: (Out a) => Maybe Int -> Channel -> (Msg -> a) -> Score (Mix (NoSE a))
pgmidi mchn = genMidi (Pgmassign mchn)

genMidi :: (Out a) => MidiType -> Channel -> (Msg -> a) -> Score (Mix (NoSE a))
genMidi midiType chn f = temp $ Mid $ mkInstr getMidiArity Msg f (Just (midiType, chn))
    where getMidiArity = mkArity (const 0) outArity
-}

-- | Constructs the effect that applies a given function on every channel.
effect :: (CsdTuple a, Out a) => (Sig -> Sig) -> (a -> a)
effect f = toCsdTuple . fmap (toE . f . fromE) . fromCsdTuple

-- | Constructs the effect that applies a given function with side effect 
-- (it uses random opcodes or delays) on every channel.
effectS :: (CsdTuple a, Out a) => (Sig -> SE Sig) -> (a -> SE a)
effectS f a = fmap fromOut $ mapM f =<< toOut a

tempAs :: Score b -> a -> Score a
tempAs a = stretch (dur a) . temp

