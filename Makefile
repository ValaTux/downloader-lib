.PHONY: tests

tests:
	@meson setup --reconfigure build-tests -Dtests=true . >/dev/null 2>&1 || (rm -rf build-tests && meson setup build-tests -Dtests=true .)
	meson compile -C build-tests
	meson test -C build-tests --verbose
