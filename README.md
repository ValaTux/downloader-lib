# vala-downloader-lib

A small Vala library for downloading files with optional speed limiting.

## Contents

- [Features](#features)
- [Public API (summary)](#public-api-summary)
- [Example: synchronous download](#example-synchronous-download)
- [Example: asynchronous download](#example-asynchronous-download)
- [Example: queued downloads (multiple files)](#example-queued-downloads-multiple-files)
- [Use In Other Projects](#use-in-other-projects)
- [Quick init (dependency setup)](#quick-init-dependency-setup)
- [Install via Vamposer](#install-via-vamposer)
- [Build](#build)
- [Test](#test)
- [Dependencies](#dependencies)
- [License](#license)

## Features

- Synchronous and asynchronous download methods
- Optional speed limits in B/s, KB/s, MB/s, or GB/s
- Structured download result object with status and metrics
- Built on top of GLib/GIO and libsoup 3

## Public API (summary)

Namespace: `ValaTux.Downloader`

- `Manager`
  - `download(string url, string dest_path) -> Result`
  - `download_async(string url, string dest_path) -> Result`
	- `add_to_download(string url, string dest_path) -> BatchDownloadResult`
	- `download_queued(bool clear_after_download = true) -> Gee.ArrayList<BatchDownloadResult>`
	- `download_queued_async(bool clear_after_download = true) -> Gee.ArrayList<BatchDownloadResult>`
	- `clear_download_queue()`
	- `download_many(Gee.List<DownloadRequest>) -> Gee.ArrayList<BatchDownloadResult>`
	- `download_many_async(Gee.List<DownloadRequest>) -> Gee.ArrayList<BatchDownloadResult>`
  - `set_speed_limit_in_bytes(int64)`
  - `set_speed_limit_in_kilobytes(int64)`
  - `set_speed_limit_in_megabytes(int64)`
  - `set_speed_limit_in_gigabytes(int64)`
- `DownloadRequest`
	- `url` (`string`)
	- `dest_path` (`string`)
- `BatchDownloadResult`
	- `url` (`string`)
	- `dest_path` (`string`)
	- `result` (`Result?`)
	- `error_message` (`string?`)
	- `is_successful` (`bool`)
- `Result`
  - `is_downloaded` (`bool`)
  - `actual_speed_bps` (`int64`)
  - `remaining_time` (`int64`, seconds, `-1` when unknown)
  - `status_code` (`uint`, HTTP status)
  - `get_remaining_time_in_seconds() -> int64`
  - `get_remaining_time_in_minutes() -> int64`
  - `get_remaining_time_in_hours() -> int64`
  - `get_remaining_time_in_days() -> int64`
  - `get_actual_speed_in_kilobytes() -> int64`
  - `get_actual_speed_in_megabytes() -> int64`
  - `get_actual_speed_in_gigabytes() -> int64`

## Example: synchronous download

```vala
using ValaTux.Downloader;

int main (string[] args) {
	var manager = new Manager ();
	manager.set_speed_limit_in_megabytes (2);

	try {
		var result = manager.download (
			"https://example.com/file.zip",
			"/tmp/file.zip"
		);

		stdout.printf ("Downloaded: %s\n", result.is_downloaded ? "yes" : "no");
		stdout.printf ("HTTP status: %u\n", result.status_code);
		stdout.printf ("Actual speed: %" + int64.FORMAT + " B/s\n", result.actual_speed_bps);
		stdout.printf ("Actual speed: %" + int64.FORMAT + " KB/s\n", result.get_actual_speed_in_kilobytes ());
		stdout.printf ("Remaining time: %" + int64.FORMAT + " s\n", result.remaining_time);
		stdout.printf ("Remaining time: %" + int64.FORMAT + " min\n", result.get_remaining_time_in_minutes ());
	} catch (Error e) {
		stderr.printf ("Download failed: %s\n", e.message);
		return 1;
	}

	return 0;
}
```

## Example: asynchronous download

```vala
using ValaTux.Downloader;

public async int run_async () {
	var manager = new Manager ();
	manager.set_speed_limit_in_kilobytes (512);

	try {
		var result = yield manager.download_async (
			"https://example.com/file.iso",
			"/tmp/file.iso"
		);

		if (!result.is_downloaded) {
			stderr.printf ("HTTP error: %u\n", result.status_code);
			return 2;
		}

		stdout.printf ("Downloaded successfully at %" + int64.FORMAT + " B/s\n", result.actual_speed_bps);
		stdout.printf ("~ %" + int64.FORMAT + " MB/s\n", result.get_actual_speed_in_megabytes ());
		return 0;
	} catch (Error e) {
		stderr.printf ("Async download failed: %s\n", e.message);
		return 1;
	}
}
```

## Example: queued downloads (multiple files)

```vala
using ValaTux.Downloader;

public async int run_batch_async () {
	var manager = new Manager ();

	var file_a = manager.add_to_download ("https://example.com/file-a.zip", "/tmp/file-a.zip");
	manager.add_to_download ("https://example.com/file-b.zip", "/tmp/file-b.zip");
	manager.add_to_download ("https://example.com/file-c.zip", "/tmp/file-c.zip");

	var results = yield manager.download_queued_async ();

	// file_a is the same object as one item in results and now contains Result metrics.
	if (file_a.result != null) {
		stdout.printf ("file-a remaining=%" + int64.FORMAT + " s\n", file_a.result.remaining_time);
	}

	foreach (var item in results) {
		if (item.error_message != null) {
			stderr.printf ("%s -> failed: %s\n", item.url, item.error_message);
			continue;
		}

		if (item.result == null || !item.result.is_downloaded) {
			uint status = item.result != null ? item.result.status_code : 0;
			stderr.printf ("%s -> HTTP status: %u\n", item.url, status);
			continue;
		}

		stdout.printf (
			"%s -> ok, speed=%" + int64.FORMAT + " B/s, remaining=%" + int64.FORMAT + " s\n",
			item.url,
			item.result.actual_speed_bps,
			item.result.remaining_time
		);
	}

	return 0;
}
```

Note: For unsuccessful downloads, `remaining_time` is `-1` (unknown).

## Use In Other Projects

Yes. The generated artifacts are intended for reuse:

- `build-release/src/libvala-downloader-lib.so*`
- `build-release/src/vapi/vala-downloader-lib.vapi`
- `build-release/src/vala-downloader-lib.h`

### Option 1: Meson subproject (recommended)

In your consumer project `meson.build`:

```meson
vala_downloader_dep = dependency('vala_downloader', fallback: ['vala-downloader-lib', 'vala_downloader_dep'])

executable('my-app',
	['src/main.vala'],
	dependencies: [vala_downloader_dep],
)
```

Then in Vala code:

```vala
using ValaTux.Downloader;
```

### Option 2: Installed library (pkg-config)

Install this project first:

```sh
meson setup builddir
meson compile -C builddir
meson install -C builddir
```

In your consumer `meson.build`:

```meson
vala_downloader_dep = dependency('vala-downloader-lib', method: 'pkg-config')
```

### Option 3: Local `vapi` folder in your project

If you want everything vendored inside your own repository, copy release artifacts into your consumer project, for example:

- `your-project/vapi/vala-downloader-lib.vapi`
- `your-project/lib/libvala-downloader-lib.so`
- `your-project/include/vala-downloader-lib.h`

To automate this setup, run the helper script in your consumer project root:

```sh
curl -sSfL https://raw.githubusercontent.com/ValaTux/downloader-lib/master/init-local-vapi.sh | bash
```

The script will:

- download a prebuilt release ZIP when available (fast path)
- fallback to building `vala-downloader-lib` from source when release assets are unavailable
- copy artifacts into your local `vapi/`, `lib/`, and `include/` directories
- append an idempotent helper block to your `meson.build` with reusable variables

## Install via [Vamposer](https://github.com/ValaTux/vamposer)

In your consumer project root:

```sh
vamposer require ValaTux/downloader-lib master
vamposer install
```

Then include generated Vamposer dependencies in your `meson.build`:

```meson
subdir('vamposer')

executable('my-app',
	sources,
	dependencies: [
		vamposer_deps
	]
)
```

You can also use a fixed tag or commit instead of `master`.

If you also want the test workspace, install it as a development dependency:

```sh
vamposer require --dev ValaTux/testcases master
vamposer install --dev
```

You can also run it from a local file copy:

```sh
./init-local-vapi.sh
```

Then configure your consumer `meson.build`:

```meson
executable('my-app',
	['src/main.vala'],
	dependencies: [
		dependency('glib-2.0'),
		dependency('gio-2.0'),
		dependency('libsoup-3.0'),
	],
	vala_args: ['--vapidir=' + meson.project_source_root() / 'vapi'],
	c_args: ['-I' + meson.project_source_root() / 'include'],
	link_args: ['-L' + meson.project_source_root() / 'lib', '-lvala-downloader-lib'],
)
```

And load the shared library at runtime, for example:

```sh
LD_LIBRARY_PATH=./lib ./my-app
```

## Quick init (dependency setup)

To add `vala-downloader-lib` as a Meson subproject dependency, run:

```sh
./init.sh
```

Or run it directly from GitHub:

```sh
curl -sSfL https://raw.githubusercontent.com/ValaTux/downloader-lib/refs/heads/master/init.sh -o init.sh && chmod +x init.sh && ./init.sh && rm init.sh
```

## Build

```sh
meson setup builddir
meson compile -C builddir
```

## Test

```sh
meson test -C builddir
```

or via Makefile helper:

```sh
make tests
```

## Dependencies

- glib-2.0
- gio-2.0
- libsoup-3.0
- gee-0.8

In consumer projects, use:

```meson
vala_downloader_dep = dependency('vala_downloader', fallback: ['vala-downloader-lib', 'vala_downloader_dep'])
```

Then add `vala_downloader_dep` to your target dependencies.

## License

MIT (see `LICENSE`).
