.. _checkpointing:

Architectural Checkpoints
=========================

Chipyard supports generating architectural checkpoints using Spike.
These checkpoints contain a snapshot of the architectural state of a RISC-V SoC at some point in the execution of a program.
The checkpoints include the contents of cacheable memory, core architectural registers, and core CSRs.
RTL simulations of SoCs can resume execution from checkpoints after restoring the architectural state.

.. note::
   Currently, only checkpoints of single-core systems are supported

Generating Checkpoints
------------------------

``scripts/generate-ckpt.sh`` is a script that runs Spike with the right commands to generate an architectural checkpoint
``scripts/generate-ckpt.sh -h`` lists options for checkpoint generation.

Example: run the ``hello.riscv`` binary for 1000 instructions before generating a checkpoint.
This should produce a directory named ``hello.riscv.<number>.loadarch``

.. code::

   scripts/generate-ckpt.sh -b tests/hello.riscv -i 1000


Loading Checkpoints in RTL Simulation
--------------------------------------

Checkpoints can be loaded in RTL simulations with the ``LOADARCH`` flag.
The target config **MUST** use DMI-based bringup (as opposed to the default TSI-based bringup), and support fast ``LOADMEM``.
The target config should also match the architectural configuration of however Spike was configured when generating the checkpoint.

.. code::

   cd sims/vcs
   make CONFIG=dmiRocketConfig run-binary LOADARCH=../../hello.riscv.<number>.loadarch

Checkpointing Linux Binaries
----------------------------

Checkpoints can be used to run Linux binaries with the following caveats:
the binary must only use the HTIF console (i.e. the Rocket Chip Blocks UART can't be used),
and it must be built without a block device (built with an initramfs)(i.e. the IceBlk block device can't be used).
Additionally, by default Spike has a default UART device that is used during most Linux boot's.
This can be bypassed by creating a DTS without a serial device then passing it to the ``generate-ckpt.sh`` script
(you can copy the DTS of the design you want to checkpoint into - located in Chipyards ``sims/<simulator>/generated-src/`` - and modify it to pass to the checkpointing script).
