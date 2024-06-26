#!/bin/bash

set -e

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options"
    echo "  --help -h  : Display this message"
    echo "  -b <elf>   : Binary to run in spike"
    echo "  -p <pc>    : PC to take checkpoint at [default 0x80000000]"
    echo "  -i <insns> : Instructions after PC to take checkpoint at [default 0]"
    echo "  -o <out>   : Output directory to store the checkpoint in. [default <elf>.<randomnum>.loadarch]"
    echo "  -v         : Verbose"
    echo ""
    echo "  -n <n>     : Number of harts [default 1]"
    echo "  -m <isa>   : ISA to pass to spike for checkpoint generation [default rv64gc]"
    echo "  -r <mem>   : Memory regions to pass to spike. Passed to spike's '-m' flag. [default starting at 0x80000000 with 256MiB]"
    echo ""
    echo "  -d <dtb>   : DTB file to use. Passed to spike's '--dtb' flag. [default is to use none]"
    echo "  -s <dts>   : DTS file to use. Converted to a DTB then passed to spike's '--dtb' flag. [default is to use none]"
    exit "$1"
}

NHARTS=1
BINARY=""
PC="0x80000000"
INSNS=0
ISA="rv64gc"
OUTPATH=""
MEMOVERRIDE=""
VERBOSE=0
DTB=""
DTS=""
while [ "$1" != "" ];
do
    case $1 in
	-h | --help )
	    usage 3 ;;
	-n )
	    shift
	    NHARTS=$1 ;;
	-b )
	    shift
	    BINARY=$1 ;;
	-p )
	    shift
	    PC=$1 ;;
	-i )
	    shift
	    INSNS=$1 ;;
        -m )
            shift
            ISA=$1 ;;
        -o )
            shift
            OUTPATH=$1 ;;
        -r )
            shift
            MEMOVERRIDE=$1 ;;
        -v )
            VERBOSE=1 ;;
	-d )
	    shift
	    DTB=$1 ;;
	-s )
	    shift
	    DTS=$1 ;;
	* )
	    error "Invalid option $1"
	    usage 1 ;;
    esac
    shift
done

if [[ $VERBOSE -eq 1 ]] ; then
    set -x
fi

BASENAME=$(basename -- $BINARY)

if [ -z "$OUTPATH" ] ; then
    OUTPATH=$BASENAME.$((RANDOM)).loadarch
fi

echo "Generating loadarch directory $OUTPATH"
rm -rf $OUTPATH
mkdir -p $OUTPATH

SPIKEFLAGS=""

if [ ! -z "$DTS" ] ; then
    dtc -I dts -O dtb -o $OUTPATH/tmp.dtb $(readlink -f $DTS)
    SPIKEFLAGS+=" --dtb=$OUTPATH/tmp.dtb"
elif [ ! -z "$DTB" ]; then
    SPIKEFLAGS+=" --dtb=$DTB"
else
    if [ -z "$MEMOVERRIDE" ] ; then
	BASEMEM="$((0x80000000)):$((0x10000000))"
    else
	BASEMEM=$MEMOVERRIDE
    fi
    SPIKEFLAGS+="-p$NHARTS --pmpregions=0 --isa=$ISA -m$BASEMEM"
fi

LOADARCH_FILE=$OUTPATH/loadarch
RAWMEM_ELF=$OUTPATH/raw.elf
LOADMEM_ELF=$OUTPATH/mem.elf
CMDS_FILE=$OUTPATH/cmds_tmp.txt
SPIKECMD_FILE=$OUTPATH/spikecmd.sh

echo "Generating state capture spike interactive commands in $CMDS_FILE"
echo "until pc 0 $PC" >> $CMDS_FILE
echo "rs $INSNS" >> $CMDS_FILE
echo "dump" >> $CMDS_FILE
for (( h=0; h<$NHARTS; h++ ))
do
    echo "pc $h" >> $CMDS_FILE
    echo "priv $h" >> $CMDS_FILE
    echo "reg $h fcsr" >> $CMDS_FILE

    echo "reg $h vstart" >> $CMDS_FILE
    echo "reg $h vxsat" >> $CMDS_FILE
    echo "reg $h vxrm" >> $CMDS_FILE
    echo "reg $h vcsr" >> $CMDS_FILE
    echo "reg $h vtype" >> $CMDS_FILE

    echo "reg $h stvec" >> $CMDS_FILE
    echo "reg $h sscratch" >> $CMDS_FILE
    echo "reg $h sepc" >> $CMDS_FILE
    echo "reg $h scause" >> $CMDS_FILE
    echo "reg $h stval" >> $CMDS_FILE
    echo "reg $h satp" >> $CMDS_FILE

    echo "reg $h mstatus" >> $CMDS_FILE
    echo "reg $h medeleg" >> $CMDS_FILE
    echo "reg $h mideleg" >> $CMDS_FILE
    echo "reg $h mie" >> $CMDS_FILE
    echo "reg $h mtvec" >> $CMDS_FILE
    echo "reg $h mscratch" >> $CMDS_FILE
    echo "reg $h mepc" >> $CMDS_FILE
    echo "reg $h mcause" >> $CMDS_FILE
    echo "reg $h mtval" >> $CMDS_FILE
    echo "reg $h mip" >> $CMDS_FILE

    echo "reg $h mcycle" >> $CMDS_FILE
    echo "reg $h minstret" >> $CMDS_FILE

    echo "mtime" >> $CMDS_FILE
    echo "mtimecmp $h" >> $CMDS_FILE

    for (( fr=0; fr<32; fr++ ))
    do
	echo "freg $h $fr" >> $CMDS_FILE
    done
    for (( xr=0; xr<32; xr++ ))
    do
	echo "reg $h $xr" >> $CMDS_FILE
    done
    echo "vreg $h" >> $CMDS_FILE
done
echo "quit" >> $CMDS_FILE

echo "spike -d --debug-cmd=$CMDS_FILE $SPIKEFLAGS $BINARY" > $SPIKECMD_FILE

echo "Capturing state at checkpoint to spikeout"
spike -d --debug-cmd=$CMDS_FILE $SPIKEFLAGS $BINARY 2> $LOADARCH_FILE


echo "Finding tohost/fromhost in elf file to inject in new elf"
function get_symbol_value() {
    echo $(riscv64-unknown-elf-nm $2 | grep " ${1}$" | head -c 16)
}
# ensure these symbols are not 'htif_*' versions
TOHOST=$(get_symbol_value tohost $BINARY)
FROMHOST=$(get_symbol_value fromhost $BINARY)

echo "Compiling memory to elf"
ls -alh mem.0x80000000.bin
riscv64-unknown-elf-objcopy -I binary -O elf64-littleriscv mem.0x80000000.bin $RAWMEM_ELF
rm -rf mem.0x80000000.bin

riscv64-unknown-elf-ld -Tdata=0x80000000 -nmagic --defsym tohost=0x$TOHOST --defsym fromhost=0x$FROMHOST -o $LOADMEM_ELF $RAWMEM_ELF
rm -rf $RAWMEM_ELF

if [[ -z "$DTB" && -z "$DTS" ]] ; then
    echo "Ensure that (at minimum) you have memory regions corresponding to $BASEMEM in downstream RTL tooling"
fi

echo "Loadarch directory $OUTPATH created"
