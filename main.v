import os

fn main() {
	mut base_directory := "."
	if os.args.len >= 2 {
		base_directory = os.args[1]
	}

	y_files := os.walk_ext(base_directory, '.y')

	println(y_files)
}