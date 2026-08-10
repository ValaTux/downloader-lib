project('vala-downloader-lib', 'vala', 'c', version: '0.4.1')

subdir('src')
if get_option('tests')
	subdir('tests')
endif

meson.override_dependency('vala_downloader', vala_downloader_dep)
