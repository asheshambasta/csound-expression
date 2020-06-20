let 
  overlays = [(import ./overlay.nix)];
  defPkgs = import <nixpkgs> { inherit overlays; }; # add the modified csound-expression package to haskellPackages
in 
{ inherit (defPkgs.haskellPackages) csound-expression; }
