## Running the development shell

### This project uses Nix to manage all the needed dependecies with a flake based script.
- Run: `nix develop`

### It creates a development shell with Erlang and Rebar3, Haskell and all its dependencies to build the libcspm library, and extracts the FDR4 package

#### Inside the development shell you will have access to both programs: `refines` and `fdr4`
- These programs are binded to use the extracted binaries from within a FHS Environment with all the dependencies required

## About the Project
