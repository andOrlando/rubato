local gears = require "gears"
local naughty = require "naughty"

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
-- @param inter whether or not it's in an intermittent state
-- @param inter_e inter easing function
-- @param m slope
-- @param b y-intercept
-- @see timed
local function get_dx(time, duration, intro, intro_e, outro, outro_e, inter, inter_e, m, b)
	if time <= intro then
		easing = inter and inter_e or intro_e
		return easing(time / intro) * (m - b) + b

	--outro math
	elseif (duration - time) <= outro then
		return outro_e((duration - time) / outro) * m

	--otherwise
	else return m end
end

--weak table for memoizing results
local simulate_turn_mem = {}
setmetatable(simulate_turn_mem, {__mode="kv"})

--- Simulates the turn around to get the result to find a coefficient
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
local function simulate_turn(pos, duration, intro, intro_e, outro, outro_e, inter, inter_e, m, b, dt)
	local ps_time = 0
	local ps_pos = pos 
	local dx

	key = string.format("%f %f %f %s %f %s %s %s %f %f", 
			pos, duration,
			intro, intro_e,
			outro, outro_e,
			inter, inter_e,
			m, b)
	
	if simulate_turn_mem[key] then
		return simulate_turn_mem[key]
	end

	while duration - ps_time >= dt / 2 do
		--increment time
		ps_time = ps_time + dt

		--get dx, but use the pseudotime as to not mess with stuff
		dx = get_dx(ps_time, duration,
			intro, intro_e,
			outro, outro_e,
			inter, inter_e,
			m, b)
		
		--increment pos by dx
		ps_pos = ps_pos + dx * dt
	end

	simulate_turn_mem[key] = ps_pos
	return ps_pos
end

--- INTERPOLATE. bam. it still ends in a period. But this one is timed.
-- @field duration the length of the animation (1)
-- @field rate how many times per second the aniamtion refrehses (32)
-- @field pos initial position of the animation (0)
-- @field intro duration of intro (0.2)
-- @field outro duration of outro (same as intro)
-- @field easing easing method (linear)
-- @field easing_outro easing method for outro (same as easing)
-- @field easing_inter intermittent easing method (same as easing)
-- @field subscribed an initial function to subscribe (nil)
-- @return timed interpolator
-- @method timed:subscribe(func) subscribe a function to the timer refresh
-- @method timed:update_rate(rate_new) please use this function instead of
-- manually updating rate
-- @method timed:set(target_new) set the target value for pos to end at
local function timed(obj)

	--set up default arguments
	local obj = obj or {}

	obj.duration = obj.duration or 1
	obj.rate = obj.rate or def_rate
	obj.pos = obj.pos or 0

	obj.intro = obj.intro or 0.2
	obj.outro = obj.outro or obj.intro

	obj.easing = obj.easing or linear
	obj.easing_outro = obj.easing_outro or obj.easing
	obj.easing_inter = obj.easing_inter or obj.easing
	
	--subscription stuff
	local subscribed = {}
	local subscribed_i = {}
	local s_counter = 1

	--TODO: fix double pos thing
	local time				--elapsed time in seconds
	local target			--target value for pos
	local dt = 1 / obj.rate --dt based off rate
	local dx = 0			--variable slope
	local m					--maximum slope  @see obj:set
	local b					--y-intercept  @see obj:set
	local easing			--placeholder easing function variable
	local inter				--checks if it's in an intermittent state

	local ps_pos			--pseudoposition
	local coef				--dx coefficient if necessary


	local timer = gears.timer { timeout = dt }
	timer:connect_signal("timeout", function()

		--increment time
		time = time + dt
		
		--get dx
		dx = get_dx(time, obj.duration, 
			obj.intro, obj.easing.easing, 
			obj.outro, obj.easing_outro.easing, 
			inter, obj.easing_inter.easing, 
			m, b)

		--increment pos by dx
		--scale by dt and correct with coef if necessary
		obj.pos = obj.pos + dx * dt * coef
		
		--sets up when to stop by time
		--weirdness is to try to get closest to duration
		if obj.duration - time < dt / 2 then
			obj.pos = target --snaps to target in case of small error

			inter = false	 --resets intermittent
			timer:stop()	 --stops itself
		end

		--run subscribed in functions
		for _, func in ipairs(subscribed) do 
			func(obj.pos, time, dx) end

	end)



	-- Set target and begin interpolation
	function obj:set(target_new)

		target = target_new	--sets target 
		time = 0			--resets time
		coef = 1			--resets coefficient
		
		if not timer.started then 

			b = 0 --no b initially (y-intercept is 0)
			m = get_slope(obj.intro, obj.outro, obj.duration, 
				target - obj.pos, obj.easing.F, obj.easing_outro.F, b)

			timer:start() 

		else

			inter = true --it is now in an intermittent state
			b = dx		 --carries over dx in the form of b
			m = get_slope(obj.intro, obj.outro, obj.duration, 
				target - obj.pos, obj.easing_inter.F, obj.easing_outro.F, b)

			--simulate the entire sequence if necessary (to prevent overshooting)
			--overshooting only happens when the signs of m and b are different
			if b / math.abs(b) ~= m / math.abs(m) then
				
				--get the projected result
				ps_pos = simulate_turn(obj.pos, obj.duration,
					obj.intro, obj.easing.easing,
					obj.outro, obj.easing_outro.easing,
					inter, obj.easing_inter.easing,
					m, b, dt)

				--get coefficient by calculating ratio of theoretical range : experimental range
				coef = (obj.pos - target) / (obj.pos - ps_pos)
				if coef ~= coef then coef = 1 end --check for div by 0 resulting in nan

			end

		end

	end
	

	-- Methods for updating stuff

	-- update dt along with rate
	function obj:update_rate(rate_new)
		obj.rate = rate_new 
		dt = 1 / obj.rate
	end

	function obj:subscribe(func)
		subscribed[s_counter] = func
		subscribed_i[func] = s_counter
		s_counter = s_counter + 1

		--run function at pos to get it up to speed
		func(obj.pos)
	end

	--subscribe one given function
	if obj.subscribed then obj:subscribe(obj.subscribed) end

	function obj:unsubscribe(func)
		table.remove(subscribed, subscribed_i[func])
		table.remove(subscribed_i, func)
	end

	function obj:is_started() return timer.started end
	
	function obj:abort()
		inter = false
		timer:stop()
	end

	return obj
	
end

--- TODO: Targegt function.
local function target(obj)
	


	return obj
end

local function interpolate(args)
	--rate is executions/sec
	--slope is units/execution (units/sec/r)
	--pos is the initial position
	--subscribed is the list of functions to execute
	--target is the target, should be set with set
	local self = args or {}
	self.subscribed = self.subscribed or {}
	self.target = 0
	self.pos = self.pos or 0
	self.rate = self.rate or 32
	self.slope = self.slope or 1/32
	
	--sets up timer with timeout and non-timeout stuff
	self.timer = gears.timer { timeout = 1 / self.rate }
	self.timer:connect_signal("timeout", function()

		self.pos = self.pos > self.target and self.pos - self.slope or self.pos + self.slope 
		for _, func in ipairs(self.subscribed) do
			func(self.pos) end


		if (self.slope / 2) >= math.abs(self.target - self.pos) then

			self.timer:stop()

			self.pos = self.target
			for _, func in ipairs(self.subscribed) do
				func(self.pos) end
		end
	end)
	
	--set the target and begin interpolation
	function self:set(target)

		self.target = target

		--starts it if it's not going
		if not self.timer.started then
			self.timer:start() end
	end

	return self
end

return {
	interpolate = interpolate,
	set_def_rate = set_def_rate,
	timed = timed,
	target = target,
	linear = linear,
	zero = zero,
	quadratic = quadratic,
}
