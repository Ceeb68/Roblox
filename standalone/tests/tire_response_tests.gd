extends SceneTree
## Knobby-patch constitutive checks. These test real production tire forces;
## native powered corner/rough-terrain rides establish gameplay behavior.
const Tire = preload("res://physics/tire.gd")
var cfg: Dictionary
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/bike_250f.json")).Tire
	_axle_isolation()
	_capability_queries()
	_directional_budgets()
	_curve_and_combined_grip()
	_relaxation_rates()
	_full_patch_lateral_transport()
	_default_strain_energy_return()
	_transient_work_and_recovery()
	_unloaded_and_degenerate()
	print("Tire response: %s checks, %s failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("TIRE RESPONSE FAIL: " + label)
func near(actual: float, expected: float, tolerance: float, label: String) -> void:
	check(is_finite(actual) and absf(actual-expected) <= tolerance, "%s (%.8f, expected %.8f)" % [label, actual, expected])
func input_at(vx := 12.0, vy := 0.0, tread := 12.0, load := 920.0) -> Dictionary:
	return {"contact":true,"normalLoad":load,"radius":0.335,"wheelOmega":tread/0.335,
		"longitudinalVelocity":vx,"lateralVelocity":vy,"camber":0.0}
func settings() -> Dictionary:
	var result := cfg.duplicate(true)
	result.LongitudinalStiffness = 11.0
	result.LateralStiffness = 14.0
	result.LongitudinalRelaxationLength = 0.20
	result.LateralRelaxationLength = 0.16
	result.AccelerationGrip = 1.0
	result.BrakingGrip = 1.0
	result.LateralGrip = 1.0
	result.GripScale = 1.0
	result.LimitSlipWork = true
	return result
func evaluate(kappa: float, alpha: float, input: Dictionary, tune: Dictionary) -> Dictionary:
	var state := Tire.new_state()
	state.slipRatio=kappa
	state.slipAngle=alpha
	return Tire.evaluate(state,input,tune,{"Grip":0.85,"Rolling":0.025})
func _ellipse(result: Dictionary, label: String) -> void:
	var x := float(result.longitudinalForce)/float(result.capacityX) if float(result.capacityX)>0.0 else 0.0
	var y := float(result.lateralForce)/float(result.capacityY) if float(result.capacityY)>0.0 else 0.0
	check(x*x+y*y <= 1.00000000001, label+" remains within its actual anisotropic ellipse")
	check(float(result.slipPower) <= 0.0000001,label+" does not generate untracked tread work")
func _axle_isolation() -> void:
	var base := settings()
	base.Front={"LateralStiffness":14.0,"GripScale":0.95,"Nested":{"value":1}}
	base.Rear={"LateralStiffness":12.0,"GripScale":1.0,"Nested":{"value":2}}
	var front := Tire.axle_settings(base,"Front")
	var rear := Tire.axle_settings(base,"Rear")
	near(front.LateralStiffness,14.0,0.0,"Front override resolves independently")
	near(rear.LateralStiffness,12.0,0.0,"Rear override resolves independently")
	near(front.LongitudinalStiffness,11.0,0.0,"Axle inherits shared longitudinal coefficient")
	front.Nested.value=99
	near(base.Front.Nested.value,1.0,0.0,"Front cache does not mutate source config")
	near(rear.Nested.value,2.0,0.0,"Nested front tuning cannot mutate rear")
	front.GripScale=1.0
	var sample:=input_at(12.,12.*tan(deg_to_rad(2.)),12.)
	var f:=evaluate(0.,deg_to_rad(2.),sample,front)
	var r:=evaluate(0.,deg_to_rad(2.),sample,rear)
	check(absf(f.lateralForce)>absf(r.lateralForce),"Stiffer front responds more strongly before sliding")
	near(f.capacityY,r.capacityY,0.0000001,"Stronger small-slip response does not raise peak grip")
func _directional_budgets() -> void:
	var tune:=settings()
	tune.AccelerationGrip=.90
	tune.BrakingGrip=.65
	tune.LateralGrip=.80
	for direction: float in [-1.0,1.0]:
		var accelerating:=evaluate(direction,0.,input_at(direction*12.,0.,direction*14.),tune)
		var braking:=evaluate(-direction,0.,input_at(direction*12.,0.,0.),tune)
		near(accelerating.capacityX,920.*.85*.90,0.000001,"Drive uses acceleration budget in either travel direction")
		near(braking.capacityX,920.*.85*.65,0.000001,"Braking uses braking budget in either travel direction")
		near(accelerating.capacityY,920.*.85*.80,0.000001,"Lateral budget remains independent of brake and drive")
		_ellipse(accelerating,"Signed drive")
		_ellipse(braking,"Signed brake")
	var soft:=tune.duplicate(true)
	soft.GripScale=.70
	var soft_result:=evaluate(.2,.1,input_at(12.,2.,15.),soft)
	near(soft_result.capacityY,920.*.85*.80*.70,0.000001,"Per-axle GripScale scales actual independent capacity")

func _capability_queries() -> void:
	var tune := settings()
	tune.GripScale = 0.8
	tune.LateralGrip = 0.75
	tune.BrakingGrip = 0.65
	var surface := {"Grip": 0.85, "Rolling": 0.025}
	for load_value: float in [0.0, 920.0, 1800.0]:
		for braking: bool in [false, true]:
			var limits := Tire.force_limits(load_value, tune, surface, braking)
			var sample := input_at(12.0, 0.4, 0.0 if braking else 15.0, load_value)
			var result := evaluate(-0.2 if braking else 0.2, 0.05, sample, tune)
			near(limits.capacityX, result.capacityX, 0.000000001, "Capability query shares the brush's longitudinal load/soil/axle budget")
			near(limits.capacityY, result.capacityY, 0.000000001, "Capability query shares the brush's independent lateral budget")
			near(Tire.available_lateral_force(load_value, 0.0, tune, surface, braking), limits.capacityY, 0.000000001,
				"No longitudinal demand preserves the full lateral capacity")
			near(Tire.available_lateral_force(load_value, float(limits.capacityX) * 0.5, tune, surface, braking),
				float(limits.capacityY) * sqrt(0.75), 0.000000001, "Combined reserve follows the same grip ellipse")
	var normal := Tire.force_limits(920.0, tune, surface)
	near(Tire.available_lateral_force(920.0, float(normal.capacityX) * 2.0, tune, surface), 0.0, 0.0,
		"Excessive drive demand leaves no lateral reserve rather than a negative square root")
	var no_drive := tune.duplicate(true)
	no_drive.AccelerationGrip = 0.0
	near(Tire.available_lateral_force(920.0, 0.0, no_drive, surface), normal.capacityY, 0.000000001,
		"A zero longitudinal grip axis still permits pure cornering")
	near(Tire.available_lateral_force(920.0, 1.0, no_drive, surface), 0.0, 0.0,
		"An impossible longitudinal request on a degenerate ellipse has no combined reserve")
func _curve_and_combined_grip() -> void:
	var tune:=settings()
	var previous:=0.0
	for angle: float in [0.,.005,.01,.02,.04,.06,.10,.15,.25,.40,.80]:
		var result:=evaluate(0.,angle,input_at(12.,12.*tan(angle),12.),tune)
		check(-float(result.lateralForce)>=previous-0.000001,"Slip grows through a progressive curve without an abrupt breakaway cliff")
		previous=-float(result.lateralForce)
		_ellipse(result,"Lateral slip curve")
	var straight:=evaluate(0.,.12,input_at(12.,1.5,12.),tune)
	var driving:=evaluate(.16,.12,input_at(12.,1.5,14.),tune)
	var locked:=evaluate(-1.,.12,input_at(12.,1.5,0.),tune)
	check(absf(driving.lateralForce)<absf(straight.lateralForce),"Hard drive progressively consumes lateral support")
	check(absf(locked.lateralForce)<absf(straight.lateralForce),"Locked-wheel braking leaves less steering support")
	for result: Dictionary in [straight,driving,locked]:_ellipse(result,"Combined force")
	var front:=settings()
	var old:=settings()
	old.LateralStiffness=7.
	var front_force:=evaluate(0.,deg_to_rad(2.),input_at(12.,.42,12.),front)
	var old_force:=evaluate(0.,deg_to_rad(2.),input_at(12.,.42,12.),old)
	check(absf(front_force.lateralForce)>1.6*absf(old_force.lateralForce),"Normal corner slip establishes substantially firmer support without extra peak friction")
func _relaxation_rates() -> void:
	var tune:=settings()
	tune.LongitudinalRelaxationLength=.40
	tune.LateralRelaxationLength=.10
	var state:=Tire.new_state()
	var sample:=input_at(10.,1.,11.)
	Tire.step(state,sample,1./240.,tune,{"Grip":.85,"Rolling":.025})
	var target_ratio:=1./sqrt(102.25)
	var target_angle:=atan(1./sqrt(102.25))
	check(float(state.slipAngle)/target_angle>2.5*float(state.slipRatio)/target_ratio,"Separate relaxation distances make lateral response quicker without changing drive relaxation")
	var reference:=Tire.new_state()
	for hz: float in [120.,240.,480.]:
		var timed:=Tire.new_state()
		for i in range(int(hz*.25)):
			Tire.step(timed,sample,1./hz,tune,{"Grip":.85,"Rolling":.025})
		if hz==120.:reference=timed
		else:
			near(timed.slipRatio,reference.slipRatio,0.000000001,"Longitudinal transport is independent of update rate")
			near(timed.slipAngle,reference.slipAngle,0.000000001,"Lateral transport is independent of update rate")
func _transient_work_and_recovery() -> void:
	var tune:=settings()
	tune.AccelerationGrip=.8
	tune.LateralGrip=1.
	for vx: float in [-15.,0.,15.]:
		for vy: float in [-4.,-.2,.2,4.]:
			for tread: float in [-20.,0.,20.]:
				for old_slip: float in [-.3,.3]:
					var sample:=input_at(vx,vy,tread)
					sample.camber=deg_to_rad(30.)
					var result:=evaluate(old_slip,old_slip,sample,tune)
					_ellipse(result,"Reversed slip/remembered patch strain")
	var state:=Tire.new_state()
	state.slipAngle=-.30
	var sample:=input_at(10.,1.,10.)
	var time_to_recover:=INF
	var previous_force:=0.0
	for i in range(120):
		var result:=Tire.step(state,sample,1./240.,tune,{"Grip":.85,"Rolling":.025})
		check(float(result.lateralForce)<=.0000001,"Old strain cannot accelerate a new opposite slide")
		check(float(result.lateralForce)<=previous_force+.000001,"Grip recovery after slip reversal is progressive")
		previous_force=result.lateralForce
		if time_to_recover==INF and float(result.lateralForce)<-100.:time_to_recover=float(i)/240.
	check(time_to_recover<.08,"Reversed slip regains useful contact force within transported tread distance")
	var original:=state.duplicate(true)
	Tire.evaluate(state,sample,tune,{"Grip":.85,"Rolling":.025})
	check(state==original,"Pure force evaluation cannot advance recovery state")
func _unloaded_and_degenerate() -> void:
	var tune:=settings()
	for zero_axis: String in ["AccelerationGrip","BrakingGrip","LateralGrip"]:
		var altered:=tune.duplicate(true)
		altered[zero_axis]=0.
		var result:=evaluate(-.5 if zero_axis=="BrakingGrip" else .5,.3,input_at(12.,2.,0. if zero_axis=="BrakingGrip" else 20.),altered)
		check(is_finite(result.longitudinalForce) and is_finite(result.lateralForce),"Zero grip on one axis is finite")
		_ellipse(result,"Degenerate grip ellipse")
	for load: float in [0.,-10.]:
		var result:=evaluate(.5,.3,input_at(12.,2.,20.,load),tune)
		near(absf(result.longitudinalForce)+absf(result.lateralForce),0.,0.,"Nonadhesive tire produces no tangential force without support")

func _full_patch_lateral_transport() -> void:
	var tune:=settings()
	tune.LimitSlipWork=false
	# This represents the same non-spin patch velocity with two different
	# axial-spin contributions at a skewed native contact lever.
	var sample:=input_at(12.,0.,12.)
	sample.lateralSlipVelocity=.8
	var state:=Tire.new_state()
	var result:=Tire.step(state,sample,1.,tune,{"Grip":.85,"Rolling":.025})
	check(float(state.slipAngle)>.06,"Sideways tread motion at a skewed patch strains the lateral brush even when non-spin hub motion is zero")
	check(float(result.lateralForce)<-300.,"Skewed-patch grip opposes actual spinning contact motion")
	var cancelled:=input_at(12.,.8,12.)
	cancelled.lateralSlipVelocity=0.
	var zero_state:=Tire.new_state()
	var zero:=Tire.step(zero_state,cancelled,1.,tune,{"Grip":.85,"Rolling":.025})
	near(zero_state.slipAngle,0.,0.,"Axial spin cancelling non-spin lateral motion leaves an unstrained patch")
	near(zero.lateralForce,0.,0.,"A rolling skewed patch cannot acquire false lateral force from the hub-only velocity")
	var legacy:=input_at(12.,.8,12.)
	var legacy_state:=Tire.new_state()
	var fallback:=Tire.step(legacy_state,legacy,1.,tune,{"Grip":.85,"Rolling":.025})
	near(fallback.lateralForce,result.lateralForce,.0000001,"Ideal tangent contact preserves the existing lateral input API")
func _default_strain_energy_return() -> void:
	var tune:=settings()
	tune.LimitSlipWork=false
	var state:=Tire.new_state()
	state.slipAngle=-.05
	var sample:=input_at(10.,.4,10.)
	# Linear pre-sliding patch energy upper bound, SI: .5*(Fn*Cα/λ)*u²,
	# with u=λ*α. The saturating brush stores no more than that bound.
	var stored_energy_bound:=.5*920.*float(tune.LateralStiffness)*float(tune.LateralRelaxationLength)*.05*.05
	var returned_energy:=0.
	var recovery_time:=INF
	for i in range(120):
		var result:=Tire.step(state,sample,1./240.,tune,{"Grip":.85,"Rolling":.025})
		returned_energy+=maxf(0.,float(result.slipPower))/240.
		check(absf(float(result.lateralForce))<=float(result.capacityY)+.0000001,"Default relaxing patch keeps its budget while returning stored strain")
		if recovery_time==INF and float(result.lateralForce)<-100.:recovery_time=float(i)/240.
	check(returned_energy>0.,"Default brush permits a brief real strain reaction instead of clipping every positive work sample")
	check(returned_energy<=stored_energy_bound,"Returned contact work stays below the patch's initial elastic strain energy bound")
	check(recovery_time<.08,"Default riding patch recovers useful opposite-slide support within80ms")
