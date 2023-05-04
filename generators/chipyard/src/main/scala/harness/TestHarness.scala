package chipyard.harness

import chisel3._

import scala.collection.mutable.{ArrayBuffer, LinkedHashMap}
import freechips.rocketchip.diplomacy.{LazyModule}
import org.chipsalliance.cde.config.{Config, Field, Parameters}
import freechips.rocketchip.util.{ResetCatchAndSync}
import freechips.rocketchip.prci.{ClockBundle, ClockBundleParameters, ClockSinkParameters, ClockParameters}
import freechips.rocketchip.stage.phases.TargetDirKey

import chipyard.iobinders.HasIOBinders
import chipyard.clocking.{SimplePllConfiguration, ClockDividerN}
import chipyard.{ChipTop}

// -------------------------------
// Chipyard Test Harness
// -------------------------------

case object MultiChipNChips extends Field[Int](0) // 0 means ignore MultiChipParams
case class MultiChipParameters(chipId: Int) extends Field[Parameters]
case object BuildTop extends Field[Parameters => LazyModule]((p: Parameters) => new ChipTop()(p))
case object DefaultClockFrequencyKey extends Field[Double](100.0) // MHz
case object HarnessBinderClockFrequencyKey extends Field[Double](100.0) // MHz/
case object HarnessClockInstantiatorKey extends Field[() => HarnessClockInstantiator](() => new DividerOnlyHarnessClockInstantiator)
case object MultiChipIdx extends Field[Int](0)

class WithMultiChip(id: Int, p: Parameters) extends Config((site, here, up) => {
  case MultiChipParameters(`id`) => p
  case MultiChipNChips => up(MultiChipNChips) max (id + 1)
})

class WithHomogeneousMultiChip(n: Int, p: Parameters, idStart: Int = 0) extends Config((site, here, up) => {
  case MultiChipParameters(id) => if (id >= idStart && id < idStart + n) p else up(MultiChipParameters(id))
  case MultiChipNChips => up(MultiChipNChips) max (idStart + n)
})

class WithHarnessBinderClockFreqMHz(freqMHz: Double) extends Config((site, here, up) => {
  case HarnessBinderClockFrequencyKey => freqMHz
})

// A TestHarness mixing this in will
// - use the HarnessClockInstantiator clock provide
// - use BuildTop/MultiChip fields to build ChipTops
trait HasChipyardHarnessInstantiators {
  implicit val p: Parameters
  // clock/reset of the chiptop reference clock (can be different than the implicit harness clock/reset)
  private val harnessBinderClockFreq: Double = p(HarnessBinderClockFrequencyKey)
  def getHarnessBinderClockFreqHz: Double = harnessBinderClockFreq * 1000000
  def getHarnessBinderClockFreqMHz: Double = harnessBinderClockFreq

  // buildtopClock takes the refClockFreq, and drives the harnessbinders
  val harnessBinderClock = Wire(Clock())
  val harnessBinderReset = Wire(Reset())

  // classes which inherit this trait should provide the below definitions
  def implicitClock: Clock
  def implicitReset: Reset
  def success: Bool

  // This can be accessed to get new clocks from the harness
  val harnessClockInstantiator = p(HarnessClockInstantiatorKey)()

  private val chipParameters = if (p(MultiChipNChips) == 0) {
    Seq(p)
  } else {
    (0 until p(MultiChipNChips)).map { i => p(MultiChipParameters(i)).alterPartial {
      case TargetDirKey => p(TargetDirKey) // hacky fix
      case MultiChipIdx => i
    }}
  }


  // This shold be called last to build the ChipTops
  def instantiateChipTops(): Seq[LazyModule] = {
    val lazyDuts = chipParameters.zipWithIndex.map { case (q,i) =>
      LazyModule(q(BuildTop)(q)).suggestName(s"chiptop$i")
    }
    val duts = lazyDuts.map(l => Module(l.module))

    withClockAndReset (harnessBinderClock, harnessBinderReset) {
      lazyDuts.zipWithIndex.foreach {
        case (d: HasIOBinders, i: Int) => ApplyHarnessBinders(this, d.lazySystem, d.portMap)(chipParameters(i))
        case _ =>
      }

      ApplyMultiHarnessBinders(this, lazyDuts)
    }

    val harnessBinderClkBundle = harnessClockInstantiator.requestClockBundle("harnessbinder_clock", getHarnessBinderClockFreqHz)
    println(s"Harness binder clock is $harnessBinderClockFreq")
    harnessBinderClock := harnessBinderClkBundle.clock
    harnessBinderReset := harnessBinderClkBundle.reset

    // This should be assigned to whatever its the "implicit" top-level clock/reset
    val implicitHarnessClockBundle = Wire(new ClockBundle(ClockBundleParameters()))
    implicitHarnessClockBundle.clock := implicitClock
    implicitHarnessClockBundle.reset := implicitReset
    harnessClockInstantiator.instantiateHarnessClocks(implicitHarnessClockBundle)

    lazyDuts
  }
}

class TestHarness(implicit val p: Parameters) extends Module with HasChipyardHarnessInstantiators {
  val io = IO(new Bundle {
    val success = Output(Bool())
  })
  val success = WireInit(false.B)
  io.success := success

  def implicitClock = clock
  def implicitReset = reset

  instantiateChipTops()

}
