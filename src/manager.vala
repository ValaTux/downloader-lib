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

        private int64 multiplier { get; set; default = 1; }

        private Soup.Session session;
        private Gee.ArrayList<BatchDownloadResult> download_queue;

        public Manager () {
            this.session = new Soup.Session ();
            this.session.user_agent = "Vala-Downloader/1.0";
            this.download_queue = new Gee.ArrayList<BatchDownloadResult> ();
        }

        public BatchDownloadResult add_to_download (string url, string dest_path) {
            var queued_item = new BatchDownloadResult (url, dest_path);
            this.download_queue.add (queued_item);
            return queued_item;
        }

        public void clear_download_queue () {
            this.download_queue.clear ();
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

        public Result download (string url, string dest_path) throws GLib.Error {
            var file = File.new_for_path (dest_path);

            if (file.query_exists ()) {
                file.delete ();
            }

            var message = new Soup.Message ("GET", url);
            var input_stream = this.session.send (message, null);
            var output_stream = file.create (FileCreateFlags.REPLACE_DESTINATION, null);

            uint8 buffer[8192];
            int64 bytes_in_current_second = 0;
            int64 second_start_time = GLib.get_monotonic_time ();
            int64 start_time = second_start_time;
            int64 total_bytes = 0;
            int64 content_length = message.response_headers.get_content_length ();

            while (true) {
                ssize_t bytes_read = input_stream.read (buffer, null);
                if (bytes_read == 0) {
                    break;
                }

                total_bytes += bytes_read;

                size_t bytes_written;
                output_stream.write_all (buffer[0:bytes_read], out bytes_written, null);

                if (this.speed_limit_bps > 0) {
                    bytes_in_current_second += bytes_read;
                    int64 current_time = GLib.get_monotonic_time ();
                    int64 elapsed_us = current_time - second_start_time;
                    int64 expected_us = (bytes_in_current_second * 1000000) / this.speed_limit_bps;

                    if (elapsed_us < expected_us) {
                        GLib.Thread.usleep ((ulong) (expected_us - elapsed_us));
                    }

                    if (GLib.get_monotonic_time () - second_start_time >= 1000000) {
                        bytes_in_current_second = 0;
                        second_start_time = GLib.get_monotonic_time ();
                    }
                }
            }

            input_stream.close (null);
            output_stream.close (null);

            return build_result (message, total_bytes, start_time, content_length);
        }

        public async Result download_async (string url, string dest_path) throws GLib.Error {
            var file = File.new_for_path (dest_path);

            if (file.query_exists ()) {
                file.delete ();
            }

            var message = new Soup.Message ("GET", url);
            var input_stream = yield this.session.send_async (message, Priority.DEFAULT, null);
            var output_stream = yield file.create_async (FileCreateFlags.REPLACE_DESTINATION, Priority.DEFAULT, null);

            uint8 buffer[8192];
            int64 bytes_in_current_second = 0;
            int64 second_start_time = GLib.get_monotonic_time ();
            int64 start_time = second_start_time;
            int64 total_bytes = 0;
            int64 content_length = message.response_headers.get_content_length ();

            while (true) {
                ssize_t bytes_read = yield input_stream.read_async (buffer, Priority.DEFAULT, null);
                if (bytes_read == 0) break;

                total_bytes += bytes_read;

                size_t bytes_written;
                yield output_stream.write_all_async (buffer[0:bytes_read], Priority.DEFAULT, null, out bytes_written);

                if (this.speed_limit_bps > 0) {
                    bytes_in_current_second += bytes_read;
                    int64 current_time = GLib.get_monotonic_time ();
                    int64 elapsed_us = current_time - second_start_time;
                    int64 expected_us = (bytes_in_current_second * 1000000) / this.speed_limit_bps;

                    if (elapsed_us < expected_us) {
                        uint delay_ms = (uint) ((expected_us - elapsed_us) / 1000);
                        if (delay_ms > 0) {
                            yield async_sleep (delay_ms);
                        }
                    }

                    if (GLib.get_monotonic_time () - second_start_time >= 1000000) {
                        bytes_in_current_second = 0;
                        second_start_time = GLib.get_monotonic_time ();
                    }
                }
            }

            yield input_stream.close_async (Priority.DEFAULT, null);
            yield output_stream.close_async (Priority.DEFAULT, null);

            return build_result (message, total_bytes, start_time, content_length);
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

            foreach (var item in this.download_queue) {
                queued_items.add (item);
            }

            foreach (var item in queued_items) {
                item.result = null;
                item.error_message = null;

                try {
                    item.result = download (item.url, item.dest_path);
                } catch (Error e) {
                    item.error_message = e.message;
                }
            }

            if (clear_after_download) {
                this.download_queue.clear ();
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

            foreach (var item in this.download_queue) {
                queued_items.add (item);
            }

            int pending = queued_items.size;

            if (pending == 0) {
                return queued_items;
            }

            var loop = new MainLoop (null, false);

            foreach (var item in queued_items) {
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

            if (clear_after_download) {
                this.download_queue.clear ();
            }

            return queued_items;
        }
    }
}
