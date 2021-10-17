import os

fn main() {
	mut base_directory := "."
	if os.args.len >= 2 {
		base_directory = os.args[1]
	}

	y_files := os.walk_ext(base_directory, '.y')

	generated_file_name := 'app.v'
	// create empty file
	if os.exists(generated_file_name) {
		panic('generated file already exists')
	}
	mut f := os.create(generated_file_name) or { panic(err) }
	f.close()

	// iterate over all the y_files
	for y_file in y_files {
		transpile_y_file(y_file, generated_file_name)
	}
}

fn transpile_y_file(y_file string, out_file string) {
	println(y_file)
}