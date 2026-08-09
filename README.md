<div align="center">

# vala-downloader-lib

Small, practical Vala downloader library with sync/async API, queue support, and optional speed limits.

[![Language: Vala](https://img.shields.io/badge/language-Vala-4E6C8B.svg)](https://vala.dev)
[![Build: Meson](https://img.shields.io/badge/build-Meson-3D4D5C.svg)](https://mesonbuild.com)
[![License: MIT](https://img.shields.io/badge/license-MIT-2EA043.svg)](LICENSE)

</div>

## Quick Navigation

[Features](#-features) •
[Install](#-install-in-other-projects) •
[Queue Behavior](#-queue-behavior-add-during-download) •
[Examples](#-examples) •
[Build and Test](#-build-and-test) •
[API Summary](#-public-api-summary)

## 🚀 Features

- Sync and async single-file download
- Batch and queue processing APIs
- Optional speed limit in B/s, KB/s, MB/s, or GB/s
- Cancellation via Cancellable in advanced API
- Live progress callback (bytes, speed, ETA)
- Bounded retry for transient failures
- Injectable Soup.Session and custom user-agent support
- Result object with HTTP status, real speed, and remaining time
- Built on GLib/GIO + libsoup 3 + Gee

## 📦 Install In Other Projects

### Option 1: Meson subproject (recommended)

In your consumer project meson.build:

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

In your consumer meson.build:

```meson
vala_downloader_dep = dependency('vala-downloader-lib', method: 'pkg-config')
```

### Option 3: Local vapi/lib/include (vendored)

Copy artifacts from release build:

- build-release/src/libvala-downloader-lib.so*
- build-release/src/vapi/vala-downloader-lib.vapi
- build-release/src/vala-downloader-lib.h

Quick setup script from consumer project root:

```sh
curl -sSfL https://raw.githubusercontent.com/ValaTux/downloader-lib/master/init-local-vapi.sh | bash
```

The script will:

- download prebuilt release ZIP when available
- fallback to source build when assets are unavailable
- copy files into local vapi/, lib/, include/
- append an idempotent helper block to meson.build

## 🧠 Queue Behavior (Add During Download)

Queue processing now supports adding new items while a queue run is already in progress.

- New items are not lost.
- They are processed in the same queue call, in a following wave.
- With clear_after_download=true, only processed items are removed from the queue.
- Internal queue access is protected by a mutex for safe concurrent add/clear operations.

This behavior is covered by dedicated tests:

- manager/download_queue_sync_add_during_download
- manager/download_queue_async_add_during_download

### Example: add items while queue is already running

```vala
using ValaTux.Downloader;

public async int run_dynamic_queue () {
	var manager = new Manager ();

	manager.add_to_download ("https://example.com/initial-file.bin", "/tmp/initial-file.bin");

	// Add another file a bit later, while queue processing is already running.
	Timeout.add (150, () => {
		manager.add_to_download ("https://example.com/late-file.bin", "/tmp/late-file.bin");
		return false;
	});

	var results = yield manager.download_queued_async (true);

	stdout.printf ("Processed items: %d\n", results.size);
	foreach (var item in results) {
		bool ok = item.result != null && item.result.is_downloaded && item.error_message == null;
		stdout.printf ("%s -> %s\n", item.url, ok ? "ok" : "failed");
	}

	return 0;
}
```

Practical note:

- New items are picked in the next processing wave of the same queue call.
- With clear_after_download=true, only items already processed in that call are removed.
- If your app uses multiple threads, keep all queue mutations on one thread or add app-level synchronization around your own state.

## ✨ Examples

### Advanced options (cancellable + progress + retry)

```vala
using GLib;
using ValaTux.Downloader;

public async int run_with_advanced_options () {
	var manager = new Manager ();
	manager.max_retry_attempts = 1;
	manager.retry_delay_ms = 250;

	var cancellable = new Cancellable ();

	Timeout.add (2000, () => {
		cancellable.cancel ();
		return false;
	});

	try {
		var result = yield manager.download_async_with_options (
			"https://example.com/file.iso",
			"/tmp/file.iso",
			cancellable,
			(downloaded_bytes, content_length, actual_speed_bps, remaining_time) => {
				stdout.printf (
					"downloaded=%" + int64.FORMAT + " bytes, speed=%" + int64.FORMAT + " B/s, eta=%" + int64.FORMAT + " s\n",
					downloaded_bytes,
					actual_speed_bps,
					remaining_time
				);
			}
		);

		stdout.printf ("status=%u downloaded=%s\n", result.status_code, result.is_downloaded ? "yes" : "no");
		return 0;
	} catch (IOError.CANCELLED e) {
		stderr.printf ("Cancelled by user\n");
		return 2;
	} catch (Error e) {
		stderr.printf ("Download failed: %s\n", e.message);
		return 1;
	}
}
```

### Synchronous download

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

### Asynchronous download

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

### Queued downloads (multiple files)

```vala
using ValaTux.Downloader;

public async int run_batch_async () {
	var manager = new Manager ();

	var file_a = manager.add_to_download ("https://example.com/file-a.zip", "/tmp/file-a.zip");
	manager.add_to_download ("https://example.com/file-b.zip", "/tmp/file-b.zip");
	manager.add_to_download ("https://example.com/file-c.zip", "/tmp/file-c.zip");

	var results = yield manager.download_queued_async ();

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

Note: for unsuccessful downloads, remaining_time is -1 (unknown).

## 🔧 Quick Init

To add vala-downloader-lib as a Meson subproject dependency:

```sh
./init.sh
```

Or run it directly from GitHub:

```sh
curl -sSfL https://raw.githubusercontent.com/ValaTux/downloader-lib/refs/heads/master/init.sh -o init.sh && chmod +x init.sh && ./init.sh && rm init.sh
```

## 🧩 Install via Vamposer

In your consumer project root:

```sh
vamposer require ValaTux/downloader-lib master
vamposer install
```

In your consumer meson.build:

```meson
subdir('vamposer')

executable('my-app',
	sources,
	dependencies: [
		vamposer_deps
	]
)
```

If you also want test workspace as a dev dependency:

```sh
vamposer require --dev ValaTux/testcases master
vamposer install --dev
```

## 🛠 Build and Test

Build:

```sh
meson setup builddir
meson compile -C builddir
```

Test:

```sh
meson test -C builddir
```

Or via Makefile helper:

```sh
make tests
```

## 📚 Public API Summary

Namespace: ValaTux.Downloader

- Manager
  - download(string url, string dest_path) -> Result
  - download_async(string url, string dest_path) -> Result
	- download_with_options(string url, string dest_path, Cancellable? cancellable = null, DownloadProgressCallback? progress_callback = null) -> Result
	- download_async_with_options(string url, string dest_path, Cancellable? cancellable = null, DownloadProgressCallback? progress_callback = null) -> Result
  - add_to_download(string url, string dest_path) -> BatchDownloadResult
  - download_queued(bool clear_after_download = true) -> Gee.ArrayList<BatchDownloadResult>
  - download_queued_async(bool clear_after_download = true) -> Gee.ArrayList<BatchDownloadResult>
  - clear_download_queue()
  - download_many(Gee.List<DownloadRequest>) -> Gee.ArrayList<BatchDownloadResult>
  - download_many_async(Gee.List<DownloadRequest>) -> Gee.ArrayList<BatchDownloadResult>
	- set_session(Soup.Session)
	- get_session() -> Soup.Session
	- set_user_agent(string user_agent)
  - set_speed_limit_in_bytes(int64)
  - set_speed_limit_in_kilobytes(int64)
  - set_speed_limit_in_megabytes(int64)
  - set_speed_limit_in_gigabytes(int64)
	- max_retry_attempts (uint)
	- retry_delay_ms (uint)
	- retry_on_http_failure (bool)
- DownloadProgressCallback
	- (downloaded_bytes, content_length, actual_speed_bps, remaining_time)
- DownloadRequest
  - url (string)
  - dest_path (string)
- BatchDownloadResult
  - url (string)
  - dest_path (string)
  - result (Result?)
  - error_message (string?)
  - is_successful (bool)
- Result
  - is_downloaded (bool)
  - actual_speed_bps (int64)
  - remaining_time (int64, seconds, -1 when unknown)
  - status_code (uint, HTTP status)
  - get_remaining_time_in_seconds() -> int64
  - get_remaining_time_in_minutes() -> int64
  - get_remaining_time_in_hours() -> int64
  - get_remaining_time_in_days() -> int64
  - get_actual_speed_in_kilobytes() -> int64
  - get_actual_speed_in_megabytes() -> int64
  - get_actual_speed_in_gigabytes() -> int64

## 📋 Dependencies

- glib-2.0
- gio-2.0
- libsoup-3.0
- gee-0.8

In consumer projects:

```meson
vala_downloader_dep = dependency('vala_downloader', fallback: ['vala-downloader-lib', 'vala_downloader_dep'])
```

Then add vala_downloader_dep to your target dependencies.

## 📄 License

MIT (see LICENSE).
