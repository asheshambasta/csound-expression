self: super:
let 
  # Filter the source based on the gitignore file. The path is the source path,
  # in which the gitignore should reside under `.gitignore`.
  gitignore = path:
    super.nix-gitignore.gitignoreSourcePure [ (path + /.gitignore) ] path;

  csoundOverrides = selfh: superh:
  let src = gitignore ./.; 
      # typedSrc = builtins.fetchGit { 
      #   url = "ssh://git@github.com/asheshambasta/csound-expression-typed.git";
      #   rev = "3dbf5501ce5620f22b3ca8dbee65d3e9d9aec6cb";
      #   ref = "master";
      # };
  in { csound-expression = selfh.callCabal2nix "csound-expression" src { };
       # csound-expression-typed = selfh.callCabal2nix "csound-expression-typed" typedSrc {};
     };
in {
  haskellPackages = super.haskellPackages.override (old: {
    overrides =
    super.lib.composeExtensions (old.overrides or (_: _: { })) csoundOverrides;
  });
}
