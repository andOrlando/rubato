# interpolate

Basically like [awestore](https://github.com/K4rakara/awestore) but not really.

The general premise of this is that I don't understand how awestore works. That
and I really wanted to be able to have an interpolator that didn't have a set
time. That being said, I haven't made an interpolateor that doesn't have a set
time yet, so I just have this instead. It's an awestore clone, but from what I
can tell it does things a little differently. It essentially allows you to
construct your slope curve much more meticulously.

![Example Slope Curve](./images/trapezoid.png)

You construct a slope curve like this. Except you don't specify the height or
anything, just the easing function, the intro duration and the total duration.
It calculates the height it should be at to travel whatever distance you like
using the below unecessarily complicated formula;

![Formula](./images/formula.png)

Furthermore, with this method, it makes you turning around as clean as can be.
Are you in the middle of an animation? Well fret not because should you start
another animation it will take into account the current slope and use it to
generate the subsequent one (in the formula, it's b) to make interruptions
buttery smooth.

![Badly drawn example](./images/double_trapezoid.png)

To actually calculate the position, it adds or substracts the y-value of the
slope curve from the current position to simulate the antiderivative. There are
a couple minor problems, however. When interrupting, should you go from dx to a
different dx of the same sign, it will very slightly undershoot. Normally if you
go from a dx to a dx of a different sign it would overshoot, but this simulates
the simulation (??) to correct for this (because while undershooting isn't
really noticible, overshooting certainly is). In the future these corrections
will probably be made more configurable.

<img src="./images/undershooting.png" width="250" height="400">

I'm also planning on writing a "target" function because that is what I
originally intended this to be for. It'll be solving for time instead of the
maximum slope, so that'll be a fun xournalpp mess.
