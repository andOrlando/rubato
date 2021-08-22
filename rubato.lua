local gears = require "gears"

--- Linear easing (in quotes).
local linear = {
	F = 0.5,
	easing = function(t) return t end
}

--- Sublinear (?) easing.
local zero = {
	F = 1,
	easing = function(t) return 1 end
}

--- Quadratic easing.
local quadratic = {
	F = 1/3,
	easing = function(t) return t * t end
}

--bouncy constants
local b_cs = {
	c1 = 6 * math.pi - 3 * math.sqrt(3) * math.log(2),
	c2 = math.sqrt(3) * math.pi,
	c3 = 6 * math.sqrt(3) * math.log(2),
	c4 = 6 * math.pi - 6147 * math.sqrt(3) * math.log(2),
	c5 = 46 * math.pi / 6
}

--the bouncy one as seen in the readme
local bouncy = {
	F = (20 * math.pi - (10 * math.log(2) - 2049) * math.sqrt(3)) /
		(20 * math.pi - 20490 * math.sqrt(3) * math.log(2)),
	easing = function(t)
		--short circuit
		if t == 0 then return 0 end
		if t == 1 then return 1 end

		local c1 = (20 * t * math.pi) / 3 - b_cs.c5
		local c2 = math.pow(2, 10 * t + 1)
		return (b_cs.c1 + b_cs.c2 * c2 * math.cos(c1) + b_cs.c3 * c2 * math.sin(c1)) / b_cs.c4
	end
}

local def_rate = 30
--- Set default refresh rate
-- @param rate refresh rate
local function set_def_rate(rate)
	def_rate = rate
end

--- Get the slope (this took me forever to find).
-- @param i intro duration
-- @param o outro duration
-- @param t total duration
-- @param d distance
-- @param F_1 value of the antiderivate at 1: F_1(1)
-- @param F_2 value of the outro antiderivative at 1: F_2(1)
-- @param[opt] b y-intercept
-- @return m the slope
-- @see timed
local function get_slope(i, o, t, d, F_1, F_2, b)
	return (d + i * b * (F_1 - 1)) / (i * (F_1 - 1) + o * (F_2 - 1) + t)
end

--- Get the dx based off of a bunch of factors
-- @param time current time
-- @param duration total duration
-- @param intro intro duration
-- @param intro_e intro easing function
-- @param outro outro duration
-- @param outro_e outro easing funciton
-- @param m slope
-- @param b y-intercept
-- @see timed
local function get_dx(time, duration, intro, intro_e, outro, outro_e, m, b)
	if time <= intro then
		return intro_e(time / intro) * (m - b) + b

	--outro math
	elseif (duration - time) <= outro then
		return outro_e((duration - time) / outro) * m

	--otherwise
	else return m end
end

--weak table for memoizing results
local simulate_easing_mem = {}
setmetatable(simulate_easing_mem, {__mode="kv"})

--- Simulates the easing to get the result to find a coefficient
-- @param pos initial position
-- @param duration duration
-- @param intro intro duration
-- @param intro_e intro easing function
-- @param outro outro duration
-- @param outro_e outro easing funciton
-- @param inter whether or not it's in an intermittent state
-- @param inter_e inter easing function
-- @param m slope
-- @param b y-intercept
-- @param dt change in time
-- @see timed
local function simulate_easing(pos, duration, intro, intro_e, outro, outro_e, m, b, dt)
	local ps_time = 0
	local ps_pos = pos
	local dx

	key = string.format("%f %f %f %s %f %s %s %s",
		pos, duration,
		intro, intro_e,
		outro, outro_e,
		m, b)

	if simulate_easing_mem[key] then
		return simulate_easing_mem[key]
	end

	while duration - ps_time >= dt / 2 do
		--increment time
		ps_time = ps_time + dt

		--get dx, but use the pseudotime as to not mess with stuff
		dx = get_dx(ps_time, duration,
			intro, intro_e,
			outro, outro_e,
			m, b)

		--increment pos by dx
		ps_pos = ps_pos + dx * dt
	end

	simulate_easing_mem[key] = ps_pos
	return ps_pos
end

local function subscribable(obj)
	local obj = obj or {}
	local subscribed = {}
	local subscribed_i = {}
	local s_counter = 0

	function obj:subscribe(func)
		subscribed[s_counter] = func
		subscribed_i[func] = s_counter
		s_counter = s_counter + 1

		if self.subscribe_callback then self.subscribe_callback(func) end
	end

	function obj:unsubscribe(func)
		table.remove(subscribed, subscribed_i[func])
		table.remove(subscribed_i, func)
	end

	function obj:fire(...) for _, func in pairs(subscribed) do func(...) end end

	return obj
end

--- INTERPOLATE. bam. it still ends in a period. But this one is timed.
-- @field duration the length of the animation (1)
-- @field rate how many times per second the aniamtion refrehses (32)
-- @field pos initial position of the animation (0)
-- @field intro duration of intro (0.2)
-- @field outro duration of outro (same as intro)
-- @field inter duration of intermittent time (same as intro)
-- @field easing easing method (linear)
-- @field easing_outro easing method for outro (same as easing)
-- @field easing_inter intermittent easing method (same as easing)
-- @field subscribed an initial function to subscribe (nil)
-- @field prop_intro whether or not the durations given from intro, outro
-- and inter are proportional or just static times
-- @return timed interpolator
-- @method timed:subscribe(func) subscribe a function to the timer refresh
-- @method timed:update_rate(rate_new) please use this function instead of
-- manually updating rate
-- @method timed:set(target_new) set the target value for pos to end at
local function timed(args)

	local obj = subscribable()

	--set up default arguments
	obj.duration = args.duration or 1
	obj.rate = args.rate or def_rate
	obj.pos = args.pos or 0

	obj.prop_intro = args.prop_intro or false

	obj.intro = args.intro or 0.2
	obj.inter = args.inter or args.intro

	--set args.outro nicely based off how large args.intro is
	if obj.intro > (obj.prop_intro and 0.5 or obj.duration) and not args.outro then
		obj.outro = math.max((args.prop_intro and 1 or args.duration - args.intro), 0)

	elseif not args.outro then obj.outro = args.intro
	else obj.outro = args.outro end

	--assert that these values are valid
	assert(obj.intro + obj.outro <= obj.duration or obj.prop_intro, "Intro and Outro must be less than or equal to total duration")
	assert(obj.intro + obj.outro <= 1 or not prop_intro, "Proportional Intro and Outro must be less than or equal to 1")

	obj.easing = args.easing or linear
	obj.easing_outro = args.easing_outro or obj.easing
	obj.easing_inter = args.easing_inter or obj.easing

	obj.override_simulate = args.override_simulate or true

	obj.log = args.log or false
	obj.awestore_compat = args.awestore_compat or false


	-- annoying awestore compatibility
	if obj.awestore_compat then
		obj.initial = obj.pos
		obj.last = 0

		function obj:initial() return obj.initial end
		function obj:last() return obj.last end

		obj.started = subscribable()
		obj.ended = subscribable()

	end

	--TODO: fix double pos thing
	local time = 0			--elapsed time in seconds
	local target			--target value for pos
	local dt = 1 / obj.rate	--dt based off rate
	local dx = 0			--variable slope
	local m					--maximum slope  @see obj:set
	local b					--y-intercept  @see obj:set
	local easing			--placeholder easing function variable
	local is_inter			--checks if it's in an intermittent state

	local ps_pos			--pseudoposition
	local coef				--dx coefficient if necessary


	local timer = gears.timer { timeout = dt }
	timer:connect_signal("timeout", function()

		--increment time
		time = time + dt

		--get dx
		dx = get_dx(time, obj.duration,
			(is_inter and obj.inter or obj.intro) * (obj.prop_intro and obj.duration or 1),
			is_inter and obj.easing_inter.easing or obj.easing.easing,
			obj.outro * (obj.prop_intro and obj.duration or 1),
			obj.easing_outro.easing,
			m, b)



		--increment pos by dx
		--scale by dt and correct with coef if necessary
		obj.pos = obj.pos + dx * dt * coef

		--sets up when to stop by time
		--weirdness is to try to get closest to duration
		if obj.duration - time < dt / 2 then
			obj.pos = target --snaps to target in case of small error
			time = obj.duration --snaps time to duration

			is_inter = false --resets intermittent
			timer:stop()	 --stops itself

			-- awestore compatibility....
			if obj.awestore_compat then obj.ended:fire(obj.pos, time, dx) end
		end

		--run subscribed in functions
		obj:fire(obj.pos, time, dx)
	end)


	-- Set target and begin interpolation
	function obj:set(target_new)

		--disallow setting it twice (because it makes it go wonky)
		if target == target_new then return end

		target = target_new	--sets target
		time = 0			--resets time
		coef = 1			--resets coefficient

		-- does annoying awestore compatibility
		if obj.awestore_compat then
			obj.last = target
			obj.started:fire(obj.pos, time, dx)
		end


		is_inter = timer.started

		b = timer.started and dx or 0
		m = get_slope(is_inter and obj.easing_inter.F or obj.easing.F,
		    (is_inter and obj.inter or obj.intro) * (obj.prop_intro and obj.duration or 1),
		    obj.outro * (obj.prop_intro and obj.duration or 1),
		    obj.duration,
		    target - obj.pos,
		    is_inter and obj.easing_inter.F or obj.easing.F,
		    obj.easing_outro.F,
		    b)

		if not override_simulate or b / math.abs(b) ~= m / math.abs(m) then
			ps_pos = simulate_easing(obj.pos, obj.duration,
				(is_inter and obj.inter or obj.intro) * (obj.prop_intro and obj.duration or 1),
				is_inter and obj.easing_inter.easing or obj.easing.easing,
				obj.outro * (obj.prop_intro and obj.duration or 1),
				obj.easing_outro.easing,
				m, b, dt)

			--get coefficient by calculating ratio of theoretical range : experimental range
			coef = (obj.pos - target) / (obj.pos - ps_pos)
			if coef ~= coef then coef = 1 end --check for div by 0 resulting in nan
		end

		if not timer.started then timer:start() end

	end

	-- Methods for updating stuff
	-- update dt along with rate
	function obj:update_rate(rate_new)
		obj.rate = rate_new
		dt = 1 / obj.rate
	end

	function obj:reset(func)
		time = 0
		target = nil
		dt = 1 / obj.rate
		dx = 0
		m = nil
		b = nil
		is_inter = false
		coef = 1
	end

	--subscribe stuff
	obj.subscribe_callback = function(func) func(obj.pos, time, dt) end
	if args.subscribed ~= nil then obj:subscribe(args.subscribed) end

	function obj:is_started() return timer.started end

	function obj:abort()
		is_inter = false
		timer:stop()
	end

	return obj

end

--- TODO: Targegt function.
local function target(obj)



	return obj
end

return {
	set_def_rate = set_def_rate,
	timed = timed,

	target = target,
	linear = linear,
	zero = zero,
	quadratic = quadratic,
	bouncy = bouncy,
}
