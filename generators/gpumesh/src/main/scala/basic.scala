package gpumesh

import org.chipsalliance.cde.config.{Config}
import freechips.rocketchip.diplomacy.{AsynchronousCrossing}
import freechips.rocketchip.subsystem.{SBUS, MBUS}

import constellation.channel._
import constellation.routing._
import constellation.router._
import constellation.topology._
import constellation.noc._
import constellation.soc.{GlobalNoCParams}

import scala.collection.immutable.ListMap

import org.chipsalliance.cde.config.{Field, Parameters, Config}
import constellation.routing._
import constellation.topology._
import constellation.noc.{NoCParams}
import constellation.channel._
import constellation.router._
import scala.collection.immutable.ListMap
import scala.math.{floor, log10, pow, max}

class TestConfig00gpu extends NoCTesterConfig(NoCTesterParams(NoCParams(
  topology        = UnidirectionalLine(2),
  channelParamGen = (a, b) => UserChannelParams(Seq.fill(3) { UserVirtualChannelParams(3) }),
  ingresses       = Seq(0).map { i => UserIngressParams(i) },
  egresses        = Seq(1).map { i => UserEgressParams(i) },
  flows           = Seq.tabulate(1, 1) { (s, d) => FlowParams(s, d, 0) }.flatten,
  routingRelation = UnidirectionalLineRouting()
)))