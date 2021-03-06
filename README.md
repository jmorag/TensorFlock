# TensorFlock
Joseph Morag - Language Guru (jm4157@columbia.edu) 
Lauren Arnett - System Architect (lba2138@columbia.edu) 
Elena Ariza - Manager (esa2150@columbia.edu) 
Nick Buonincontri - Tester (nb2413@columbia.edu)

## Compilation of TensorFlock
### External Dependencies
TensorFlock requires the following to be installed on your local system:
- opam, version 1.2.2 or greater
- OCaml, version 4.06 or greater, installed with opam
-- Though it has not been tested we've tried to avoid language features added after 4.03; earlier versions of OCaml will likely work, but we make no guarantees.
- LLVM, version 3.8
- OCaml's LLVM bindings, version 3.8, installed with opam
-- LLVM and OCaml's LLVM bindings may use later versions but the versions must match

### Build
First, you need to declare where LLVM's binaries are located on your system. If LLVM's bin is already in your path then you can skip this step.

To declare LLVM's location cp the file named `local.example` to local.mk` In `local.mk` add this assignment: `LLVM_PATH = /path/to/llvm/bin`.

The `Makefile` contains a target to first verify `lli` can be found on the system path, then if the LLVM_PATH variable has been set - always in that order, the path takes precedence over the LLVM_PATH variable. If neither condition is met it will error with a message when attempting to run make targets that require LLVM.

If using the Docker container described below, you do not need to setup `local.mk`. The container has LLVM's bin in the system path.

Run `make` to compile TensorFlock's compiler. TensorFlock is packaged with an opam file that will install any needed dependencies as a local pin.

After running `make` the compiler will be named `toplevel.native` and can be found in the root directory of the project.

## Compiling and Executing TensorFlock Programs
The TensorFlock compiler can take one of four flags:
- `-a`: prints the AST
- `-s`: runs the semantic checker
- `-l`: prints generated LLVM IR
- `-c`: generates LLVM bytecode, saved to `output.ll`

For example the compiler is executed by running: `./toplevel.native -c tests/some_file.tf`

### "Hello World"
For ease of demonstration a `make demo` target has been added to the Makefile. This compiles the TensorFlock compiler, which in turn compiles our demo program to LLVM bytecode, which is then passed to the LLVM interpreter.

## Testing
Run `make test` to execute the test runner.

### Testing Scheme
Our test runner checks three levels of compilation: parsing, semantic checking, and codegen.

Parsing and semantic checking are verified on the basis of the exit code of the compilation process. Passing tests are expected to exit on 0, failing tests are expected to exit on some n > 0.

In addition to the manner described above, passing codegen tests are also tested by comparing the output of the executed program with a canonical value. (The value is saved in a corresponding file with the extension `.pass` eg: `some_test.tf` => `some_test.pass`

## Docker
To ensure a consistent development environment we've created a Docker image with all external dependencies installed, as well as provide build targets to make, run, and test TensorFlock in a corresponding Docker containers.

The Dockerfile, which declares how the image is built, can be found in the `docker` directory.

To use Docker, first install Docker on your host system and verify that the Docker demon is running. Then:
- `make docker-make`: runs `make` inside a container and exits
- `make docker-test`: runs `make test` inside a container and exits
- `make docker-shell`: drops you into a shell of a running container, inside `/root/TensorFlock`

Some notes about our Docker setup:
- The initial run of the container on the host will pull down the image, which is ~1GB. (We used Ubuntu 16.04 as a base system; in retrospect a smaller distro would have been better.)
- The TensorFlock directory on the host machine is effectively mounted to `/root/TensorFlock` inside the container. Disk writes on the host in this directory will appear in the client, and vice-versa.
- The container is discarded upon exit. Any changes to the client outside of `/root/TensorFlock` are lost when the container stops. This is done to maintain the consistency of the build environment as well as prevent the buildup of old containers on the host.
