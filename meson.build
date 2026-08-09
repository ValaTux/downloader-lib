project('vala-downloader-lib', 'vala', 'c', version: '0.4.0')

subdir('src')
if get_option('build_tests')
	subdir('tests')
endif

meson.override_dependency('vala_downloader', vala_downloader_dep)
