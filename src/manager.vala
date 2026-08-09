namespace ValaTux.Downloader {
    public class DownloadRequest : Object {
        public string url { get; construct set; }
        public string dest_path { get; construct set; }

        public DownloadRequest (string url, string dest_path) {
            Object (url: url, dest_path: dest_path);
        }
    }

    public class BatchDownloadResult : Object {
        public string url { get; construct set; }
        public string dest_path { get; construct set; }
        public Result? result { get; set; default = null; }
        public string? error_message { get; set; default = null; }

        public bool is_successful {
            get {
                return this.error_message == null && this.result != null && this.result.is_downloaded;
            }
        }

        public BatchDownloadResult (string url, string dest_path) {
            Object (url: url, dest_path: dest_path);
        }
    }

    public class Manager : Object {
        // Limit rychlosti v bajtech za sekundu (0 = bez limitu)
        public int64 speed_limit_bps { get; set; default = 0; }
        public uint max_retry_attempts { get; set; default = 0; }
        public uint retry_delay_ms { get; set; default = 250; }
        public bool retry_on_http_failure { get; set; default = true; }

        private Soup.Session session;
        private Gee.ArrayList<BatchDownloadResult> download_queue;
        private Mutex queue_mutex;

        public Manager (Soup.Session? session = null) {
            if (session != null) {
                this.session = session;
            } else {
                this.session = new Soup.Session ();
            }

            if (this.session.user_agent == null || this.session.user_agent == "") {
                this.session.user_agent = "Vala-Downloader/1.0";
            }

            this.download_queue = new Gee.ArrayList<BatchDownloadResult> ();
        }

        public void set_session (Soup.Session session) {
            this.session = session;

            if (this.session.user_agent == null || this.session.user_agent == "") {
                this.session.user_agent = "Vala-Downloader/1.0";
            }
        }

        public Soup.Session get_session () {
            return this.session;
        }

        public void set_user_agent (string user_agent) {
            this.session.user_agent = user_agent;
        }

        public BatchDownloadResult add_to_download (string url, string dest_path) {
            var queued_item = new BatchDownloadResult (url, dest_path);

            this.queue_mutex.lock ();
            try {
                this.download_queue.add (queued_item);
            } finally {
                this.queue_mutex.unlock ();
            }

            return queued_item;
        }

        public void clear_download_queue () {
            this.queue_mutex.lock ();
            try {
                this.download_queue.clear ();
            } finally {
                this.queue_mutex.unlock ();
            }
        }

        public void set_speed_limit_in_bytes (int64 bytes_per_second) {
            this.speed_limit_bps = bytes_per_second;
        }

        public void set_speed_limit_in_kilobytes (int64 kilobytes_per_second) {
            this.speed_limit_bps = kilobytes_per_second * ValaTux.Downloader.KILOBYTE;
        }

        public void set_speed_limit_in_megabytes (int64 megabytes_per_second) {
            this.speed_limit_bps = megabytes_per_second * ValaTux.Downloader.MEGABYTE;
        }

        public void set_speed_limit_in_gigabytes (int64 gigabytes_per_second) {
            this.speed_limit_bps = gigabytes_per_second * ValaTux.Downloader.GIGABYTE;
        }

        private Result build_result (Soup.Message message, int64 total_bytes, int64 start_time_us, int64 content_length) {
            var result = new Result ();
            result.status_code = message.status_code;
            result.is_downloaded = message.status_code == Soup.Status.OK;

            int64 elapsed_us = GLib.get_monotonic_time () - start_time_us;
            if (elapsed_us > 0 && total_bytes > 0) {
                result.actual_speed_bps = (total_bytes * 1000000) / elapsed_us;
            }

            // Remaining time is only meaningful for successful downloads.
            if (!result.is_downloaded) {
                result.remaining_time = -1;
            } else if (content_length <= 0 || total_bytes >= content_length) {
                result.remaining_time = 0;
            } else if (result.actual_speed_bps > 0) {
                int64 remaining_bytes = content_length - total_bytes;
                result.remaining_time = (remaining_bytes + result.actual_speed_bps - 1) / result.actual_speed_bps;
            } else {
                result.remaining_time = -1;
            }

            return result;
        }

        private int64 estimate_remaining_time (int64 content_length, int64 total_bytes, int64 actual_speed_bps) {
            if (content_length <= 0 || total_bytes >= content_length) {
                return 0;
            }

            if (actual_speed_bps > 0) {
                int64 remaining_bytes = content_length - total_bytes;
                return (remaining_bytes + actual_speed_bps - 1) / actual_speed_bps;
            }

            return -1;
        }

        private void emit_progress (
            DownloadProgressCallback? progress_callback,
            int64 total_bytes,
            int64 content_length,
            int64 start_time_us
        ) {
            if (progress_callback == null) {
                return;
            }

            int64 elapsed_us = GLib.get_monotonic_time () - start_time_us;
            int64 actual_speed_bps = 0;

            if (elapsed_us > 0 && total_bytes > 0) {
                actual_speed_bps = (total_bytes * 1000000) / elapsed_us;
            }

            int64 remaining_time = estimate_remaining_time (content_length, total_bytes, actual_speed_bps);
            progress_callback (total_bytes, content_length, actual_speed_bps, remaining_time);
        }

        private void remove_partial_file (File file) {
            try {
                if (file.query_exists ()) {
                    file.delete ();
                }
            } catch (Error e) {
            }
        }

        private void sleep_with_cancellable (int64 delay_us, Cancellable? cancellable) throws GLib.Error {
            int64 remaining_us = delay_us;

            while (remaining_us > 0) {
                if (cancellable != null) {
                    cancellable.set_error_if_cancelled ();
                }

                int64 step_us = remaining_us > 50000 ? 50000 : remaining_us;
                GLib.Thread.usleep ((ulong) step_us);
                remaining_us -= step_us;
            }
        }

        private async void async_sleep_with_cancellable (uint delay_ms, Cancellable? cancellable) throws GLib.Error {
            uint remaining_ms = delay_ms;

            while (remaining_ms > 0) {
                if (cancellable != null) {
                    cancellable.set_error_if_cancelled ();
                }

                uint step_ms = remaining_ms > 50 ? 50 : remaining_ms;
                yield async_sleep (step_ms);
                remaining_ms -= step_ms;
            }
        }

        private bool should_retry_http_status (uint status_code) {
            if (status_code == Soup.Status.REQUEST_TIMEOUT || status_code == 429) {
                return true;
            }

            return status_code >= 500;
        }

        private bool should_retry_error (Error e) {
            if (e is IOError.CANCELLED) {
                return false;
            }

            return true;
        }

        private Result download_once (
            string url,
            string dest_path,
            Cancellable? cancellable,
            DownloadProgressCallback? progress_callback
        ) throws GLib.Error {
            var file = File.new_for_path (dest_path);
            InputStream? input_stream = null;
            OutputStream? output_stream = null;

            try {
                if (cancellable != null) {
                    cancellable.set_error_if_cancelled ();
                }

                if (file.query_exists (cancellable)) {
                    file.delete (cancellable);
                }

                var message = new Soup.Message ("GET", url);
                input_stream = this.session.send (message, cancellable);
                output_stream = file.create (FileCreateFlags.REPLACE_DESTINATION, cancellable);

                uint8 buffer[8192];
                int64 bytes_in_current_second = 0;
                int64 second_start_time = GLib.get_monotonic_time ();
                int64 start_time = second_start_time;
                int64 total_bytes = 0;
                int64 content_length = message.response_headers.get_content_length ();

                while (true) {
                    if (cancellable != null) {
                        cancellable.set_error_if_cancelled ();
                    }

                    ssize_t bytes_read = input_stream.read (buffer, cancellable);
                    if (bytes_read == 0) {
                        break;
                    }

                    total_bytes += bytes_read;

                    size_t bytes_written;
                    output_stream.write_all (buffer[0:bytes_read], out bytes_written, cancellable);

                    emit_progress (progress_callback, total_bytes, content_length, start_time);

                    if (this.speed_limit_bps > 0) {
                        bytes_in_current_second += bytes_read;
                        int64 current_time = GLib.get_monotonic_time ();
                        int64 elapsed_us = current_time - second_start_time;
                        int64 expected_us = (bytes_in_current_second * 1000000) / this.speed_limit_bps;

                        if (elapsed_us < expected_us) {
                            sleep_with_cancellable (expected_us - elapsed_us, cancellable);
                        }

                        if (GLib.get_monotonic_time () - second_start_time >= 1000000) {
                            bytes_in_current_second = 0;
                            second_start_time = GLib.get_monotonic_time ();
                        }
                    }
                }

                input_stream.close (cancellable);
                input_stream = null;

                output_stream.close (cancellable);
                output_stream = null;

                var result = build_result (message, total_bytes, start_time, content_length);
                if (!result.is_downloaded) {
                    remove_partial_file (file);
                }

                return result;
            } catch (Error e) {
                remove_partial_file (file);
                throw e;
            } finally {
                if (input_stream != null) {
                    try {
                        input_stream.close (null);
                    } catch (Error e) {
                    }
                }

                if (output_stream != null) {
                    try {
                        output_stream.close (null);
                    } catch (Error e) {
                    }
                }
            }
        }

        private async Result download_once_async (
            string url,
            string dest_path,
            Cancellable? cancellable,
            DownloadProgressCallback? progress_callback
        ) throws GLib.Error {
            var file = File.new_for_path (dest_path);
            InputStream? input_stream = null;
            OutputStream? output_stream = null;

            try {
                if (cancellable != null) {
                    cancellable.set_error_if_cancelled ();
                }

                if (file.query_exists (cancellable)) {
                    file.delete (cancellable);
                }

                var message = new Soup.Message ("GET", url);
                input_stream = yield this.session.send_async (message, Priority.DEFAULT, cancellable);
                output_stream = yield file.create_async (FileCreateFlags.REPLACE_DESTINATION, Priority.DEFAULT, cancellable);

                uint8 buffer[8192];
                int64 bytes_in_current_second = 0;
                int64 second_start_time = GLib.get_monotonic_time ();
                int64 start_time = second_start_time;
                int64 total_bytes = 0;
                int64 content_length = message.response_headers.get_content_length ();

                while (true) {
                    if (cancellable != null) {
                        cancellable.set_error_if_cancelled ();
                    }

                    ssize_t bytes_read = yield input_stream.read_async (buffer, Priority.DEFAULT, cancellable);
                    if (bytes_read == 0) {
                        break;
                    }

                    total_bytes += bytes_read;

                    size_t bytes_written;
                    yield output_stream.write_all_async (buffer[0:bytes_read], Priority.DEFAULT, cancellable, out bytes_written);

                    emit_progress (progress_callback, total_bytes, content_length, start_time);

                    if (this.speed_limit_bps > 0) {
                        bytes_in_current_second += bytes_read;
                        int64 current_time = GLib.get_monotonic_time ();
                        int64 elapsed_us = current_time - second_start_time;
                        int64 expected_us = (bytes_in_current_second * 1000000) / this.speed_limit_bps;

                        if (elapsed_us < expected_us) {
                            uint delay_ms = (uint) ((expected_us - elapsed_us) / 1000);
                            if (delay_ms > 0) {
                                yield async_sleep_with_cancellable (delay_ms, cancellable);
                            }
                        }

                        if (GLib.get_monotonic_time () - second_start_time >= 1000000) {
                            bytes_in_current_second = 0;
                            second_start_time = GLib.get_monotonic_time ();
                        }
                    }
                }

                yield input_stream.close_async (Priority.DEFAULT, cancellable);
                input_stream = null;

                yield output_stream.close_async (Priority.DEFAULT, cancellable);
                output_stream = null;

                var result = build_result (message, total_bytes, start_time, content_length);
                if (!result.is_downloaded) {
                    remove_partial_file (file);
                }

                return result;
            } catch (Error e) {
                remove_partial_file (file);
                throw e;
            } finally {
                if (input_stream != null) {
                    try {
                        yield input_stream.close_async (Priority.DEFAULT, null);
                    } catch (Error e) {
                    }
                }

                if (output_stream != null) {
                    try {
                        yield output_stream.close_async (Priority.DEFAULT, null);
                    } catch (Error e) {
                    }
                }
            }
        }

        public Result download (string url, string dest_path) throws GLib.Error {
            return download_with_options (url, dest_path, null, null);
        }

        public async Result download_async (string url, string dest_path) throws GLib.Error {
            return yield download_async_with_options (url, dest_path, null, null);
        }

        public Result download_with_options (
            string url,
            string dest_path,
            Cancellable? cancellable = null,
            DownloadProgressCallback? progress_callback = null
        ) throws GLib.Error {
            uint attempt = 0;

            while (true) {
                if (cancellable != null) {
                    cancellable.set_error_if_cancelled ();
                }

                Result result;
                try {
                    result = download_once (url, dest_path, cancellable, progress_callback);
                } catch (Error e) {
                    bool can_retry_error = attempt < this.max_retry_attempts && should_retry_error (e);
                    if (!can_retry_error) {
                        throw e;
                    }

                    attempt++;
                    if (this.retry_delay_ms > 0) {
                        sleep_with_cancellable ((int64) this.retry_delay_ms * 1000, cancellable);
                    }
                    continue;
                }

                bool can_retry_http =
                    !result.is_downloaded &&
                    this.retry_on_http_failure &&
                    should_retry_http_status (result.status_code) &&
                    attempt < this.max_retry_attempts;

                if (!can_retry_http) {
                    return result;
                }

                attempt++;
                if (this.retry_delay_ms > 0) {
                    sleep_with_cancellable ((int64) this.retry_delay_ms * 1000, cancellable);
                }
            }
        }

        public async Result download_async_with_options (
            string url,
            string dest_path,
            Cancellable? cancellable = null,
            DownloadProgressCallback? progress_callback = null
        ) throws GLib.Error {
            uint attempt = 0;

            while (true) {
                if (cancellable != null) {
                    cancellable.set_error_if_cancelled ();
                }

                Result result;
                try {
                    result = yield download_once_async (url, dest_path, cancellable, progress_callback);
                } catch (Error e) {
                    bool can_retry_error = attempt < this.max_retry_attempts && should_retry_error (e);
                    if (!can_retry_error) {
                        throw e;
                    }

                    attempt++;
                    if (this.retry_delay_ms > 0) {
                        yield async_sleep_with_cancellable (this.retry_delay_ms, cancellable);
                    }
                    continue;
                }

                bool can_retry_http =
                    !result.is_downloaded &&
                    this.retry_on_http_failure &&
                    should_retry_http_status (result.status_code) &&
                    attempt < this.max_retry_attempts;

                if (!can_retry_http) {
                    return result;
                }

                attempt++;
                if (this.retry_delay_ms > 0) {
                    yield async_sleep_with_cancellable (this.retry_delay_ms, cancellable);
                }
            }
        }

        public Gee.ArrayList<BatchDownloadResult> download_many (Gee.List<DownloadRequest> requests) {
            var results = new Gee.ArrayList<BatchDownloadResult> ();

            foreach (var request in requests) {
                var item_result = new BatchDownloadResult (request.url, request.dest_path);

                try {
                    item_result.result = download (request.url, request.dest_path);
                } catch (Error e) {
                    item_result.error_message = e.message;
                }

                results.add (item_result);
            }

            return results;
        }

        public Gee.ArrayList<BatchDownloadResult> download_queued (bool clear_after_download = true) {
            var queued_items = new Gee.ArrayList<BatchDownloadResult> ();
            int processed_count = 0;

            while (true) {
                BatchDownloadResult? item = null;

                this.queue_mutex.lock ();
                try {
                    if (processed_count >= this.download_queue.size) {
                        break;
                    }

                    item = this.download_queue[processed_count];
                    processed_count++;
                } finally {
                    this.queue_mutex.unlock ();
                }

                if (item == null) {
                    continue;
                }

                item.result = null;
                item.error_message = null;

                try {
                    item.result = download (item.url, item.dest_path);
                } catch (Error e) {
                    item.error_message = e.message;
                }

                queued_items.add (item);
            }

            if (clear_after_download && processed_count > 0) {
                this.queue_mutex.lock ();
                try {
                    int remove_count = int.min (processed_count, this.download_queue.size);
                    for (int i = 0; i < remove_count; i++) {
                        this.download_queue.remove_at (0);
                    }
                } finally {
                    this.queue_mutex.unlock ();
                }
            }

            return queued_items;
        }

        public async Gee.ArrayList<BatchDownloadResult> download_many_async (Gee.List<DownloadRequest> requests) {
            var ordered_results = new BatchDownloadResult?[requests.size];
            int pending = requests.size;

            if (pending == 0) {
                return new Gee.ArrayList<BatchDownloadResult> ();
            }

            var loop = new MainLoop (null, false);
            int index = 0;

            foreach (var request in requests) {
                int current_index = index;
                string current_url = request.url;
                string current_dest_path = request.dest_path;

                download_async.begin (current_url, current_dest_path, (obj, res) => {
                    var item_result = new BatchDownloadResult (current_url, current_dest_path);

                    try {
                        item_result.result = download_async.end (res);
                    } catch (Error e) {
                        item_result.error_message = e.message;
                    }

                    ordered_results[current_index] = item_result;
                    pending--;

                    if (pending == 0) {
                        loop.quit ();
                    }
                });

                index++;
            }

            loop.run ();

            var results = new Gee.ArrayList<BatchDownloadResult> ();
            foreach (var item_result in ordered_results) {
                if (item_result != null) {
                    results.add (item_result);
                }
            }

            return results;
        }

        public async Gee.ArrayList<BatchDownloadResult> download_queued_async (bool clear_after_download = true) {
            var queued_items = new Gee.ArrayList<BatchDownloadResult> ();
            int processed_count = 0;

            while (true) {
                var wave_items = new Gee.ArrayList<BatchDownloadResult> ();

                this.queue_mutex.lock ();
                try {
                    if (processed_count >= this.download_queue.size) {
                        break;
                    }

                    int wave_end = this.download_queue.size;
                    for (int i = processed_count; i < wave_end; i++) {
                        wave_items.add (this.download_queue[i]);
                    }
                    processed_count = wave_end;
                } finally {
                    this.queue_mutex.unlock ();
                }

                int pending = wave_items.size;
                if (pending == 0) {
                    continue;
                }

                var loop = new MainLoop (null, false);

                foreach (var item in wave_items) {
                    var current_item = item;
                    current_item.result = null;
                    current_item.error_message = null;

                    download_async.begin (current_item.url, current_item.dest_path, (obj, res) => {
                        try {
                            current_item.result = download_async.end (res);
                        } catch (Error e) {
                            current_item.error_message = e.message;
                        }

                        pending--;

                        if (pending == 0) {
                            loop.quit ();
                        }
                    });
                }

                loop.run ();

                foreach (var item in wave_items) {
                    queued_items.add (item);
                }
            }

            if (clear_after_download && processed_count > 0) {
                this.queue_mutex.lock ();
                try {
                    int remove_count = int.min (processed_count, this.download_queue.size);
                    for (int i = 0; i < remove_count; i++) {
                        this.download_queue.remove_at (0);
                    }
                } finally {
                    this.queue_mutex.unlock ();
                }
            }

            return queued_items;
        }
    }
}
