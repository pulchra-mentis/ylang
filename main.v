import os
import nedpals.vargs

fn main() {
	mut args := vargs.new(os.args, 1)
	args.parse() 

	if("d" in args.options){

	}

	println(args.options['d'])
}