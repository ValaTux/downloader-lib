namespace AppTests {
    using GLib;
    using ValaTux.Downloader;
    using ValaTux.Testcases;

    public class DownloadFeaturesTest : BaseTest {
        construct {
            add_test ("manager/download_async_cancellable_cleans_partial_file", test_manager_download_async_cancellable_cleans_partial_file);
            add_test ("manager/download_with_options_progress_callback", test_manager_download_with_options_progress_callback);
            add_test ("manager/download_with_options_retry_on_http_500", test_manager_download_with_options_retry_on_http_500);
            add_test ("manager/download_uses_injected_session_user_agent", test_manager_download_uses_injected_session_user_agent);
        }

        public void test_manager_download_async_cancellable_cleans_partial_file () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);

            uint8[] response_body = new uint8[131072];
            for (int i = 0; i < response_body.length; i++) {
                response_body[i] = (uint8) ('A' + (i % 26));
            }

            server.add_handler (null, (srv, msg, path, query) => {
                msg.set_status (Soup.Status.OK, null);
                msg.set_response ("application/octet-stream", Soup.MemoryUse.COPY, response_body);
            });

            try {
                assert (server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY));
            } catch (Error e) {
                assert_not_reached ();
            }

            var uris = server.get_uris ();
            string base_uri = uris.nth_data (0).to_string ();
            string url = base_uri.has_suffix ("/") ? @"$(base_uri)cancel-test" : @"$(base_uri)/cancel-test";

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string dest_path = Path.build_filename (temp_dir, "downloaded-cancel.bin");
            var manager = new Manager ();
            manager.set_speed_limit_in_bytes (65536);

            var cancellable = new Cancellable ();
            var loop = new MainLoop (null, false);
            Result? result = null;
            Error? err = null;

            Timeout.add (100, () => {
                cancellable.cancel ();
                return false;
            });

            manager.download_async_with_options.begin (url, dest_path, cancellable, null, (obj, res) => {
                try {
                    result = manager.download_async_with_options.end (res);
                } catch (Error e) {
                    err = e;
                }
                loop.quit ();
            });

            loop.run ();

            assert (result == null);
            assert (err != null);
            assert (err is IOError.CANCELLED);
            assert (!File.new_for_path (dest_path).query_exists ());

            DirUtils.remove (temp_dir);
            server.disconnect ();
        }

        public void test_manager_download_with_options_progress_callback () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);

            uint8[] response_body = new uint8[65536];
            for (int i = 0; i < response_body.length; i++) {
                response_body[i] = (uint8) ('a' + (i % 26));
            }

            server.add_handler (null, (srv, msg, path, query) => {
                msg.set_status (Soup.Status.OK, null);
                msg.set_response ("application/octet-stream", Soup.MemoryUse.COPY, response_body);
            });

            try {
                assert (server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY));
            } catch (Error e) {
                assert_not_reached ();
            }

            var uris = server.get_uris ();
            string base_uri = uris.nth_data (0).to_string ();
            string url = base_uri.has_suffix ("/") ? @"$(base_uri)progress-test" : @"$(base_uri)/progress-test";

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string dest_path = Path.build_filename (temp_dir, "downloaded-progress.bin");
            var manager = new Manager ();
            manager.set_speed_limit_in_bytes (65536);

            int progress_calls = 0;
            int64 last_downloaded = 0;

            var loop = new MainLoop (null, false);
            Result? result = null;
            Error? err = null;

            var download_thread = new Thread<bool> ("sync-download-progress", () => {
                try {
                    result = manager.download_with_options (
                        url,
                        dest_path,
                        null,
                        (downloaded_bytes, content_length, actual_speed_bps, remaining_time) => {
                            progress_calls++;
                            last_downloaded = downloaded_bytes;
                        }
                    );
                } catch (Error e) {
                    err = e;
                }

                Idle.add (() => {
                    loop.quit ();
                    return false;
                });

                return true;
            });

            loop.run ();
            download_thread.join ();

            assert (err == null);
            assert (result != null);
            assert (result.is_downloaded);
            assert (progress_calls > 0);
            assert (last_downloaded > 0);

            FileUtils.remove (dest_path);
            DirUtils.remove (temp_dir);
            server.disconnect ();
        }

        public void test_manager_download_with_options_retry_on_http_500 () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);
            string ok_payload = "retry-success";
            uint8[] ok_response_body = ok_payload.data;
            int request_count = 0;

            server.add_handler (null, (srv, msg, path, query) => {
                request_count++;

                if (request_count == 1) {
                    msg.set_status (Soup.Status.INTERNAL_SERVER_ERROR, null);
                    return;
                }

                msg.set_status (Soup.Status.OK, null);
                msg.set_response ("text/plain", Soup.MemoryUse.COPY, ok_response_body);
            });

            try {
                assert (server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY));
            } catch (Error e) {
                assert_not_reached ();
            }

            var uris = server.get_uris ();
            string base_uri = uris.nth_data (0).to_string ();
            string url = base_uri.has_suffix ("/") ? @"$(base_uri)retry-test" : @"$(base_uri)/retry-test";

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string dest_path = Path.build_filename (temp_dir, "downloaded-retry.txt");
            var manager = new Manager ();
            manager.max_retry_attempts = 1;

            var loop = new MainLoop (null, false);
            Result? result = null;
            Error? err = null;

            var download_thread = new Thread<bool> ("sync-download-retry", () => {
                try {
                    result = manager.download_with_options (url, dest_path);
                } catch (Error e) {
                    err = e;
                }

                Idle.add (() => {
                    loop.quit ();
                    return false;
                });

                return true;
            });

            loop.run ();
            download_thread.join ();

            assert (err == null);
            assert (result != null);
            assert (result.is_downloaded);
            assert (result.status_code == Soup.Status.OK);
            assert (request_count == 2);

            string downloaded;
            try {
                FileUtils.get_contents (dest_path, out downloaded);
            } catch (FileError e) {
                assert_not_reached ();
            }

            assert (downloaded == ok_payload);

            FileUtils.remove (dest_path);
            DirUtils.remove (temp_dir);
            server.disconnect ();
        }

        public void test_manager_download_uses_injected_session_user_agent () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);
            string expected_user_agent = "DownloaderLib-Test-UA/1.0";
            string? received_user_agent = null;

            string payload = "ua-ok";
            uint8[] response_body = payload.data;

            server.add_handler (null, (srv, msg, path, query) => {
                received_user_agent = msg.get_request_headers ().get_one ("User-Agent");
                msg.set_status (Soup.Status.OK, null);
                msg.set_response ("text/plain", Soup.MemoryUse.COPY, response_body);
            });

            try {
                assert (server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY));
            } catch (Error e) {
                assert_not_reached ();
            }

            var uris = server.get_uris ();
            string base_uri = uris.nth_data (0).to_string ();
            string url = base_uri.has_suffix ("/") ? @"$(base_uri)ua-test" : @"$(base_uri)/ua-test";

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string dest_path = Path.build_filename (temp_dir, "downloaded-ua.txt");

            var custom_session = new Soup.Session ();
            custom_session.user_agent = expected_user_agent;

            var manager = new Manager (custom_session);
            var loop = new MainLoop (null, false);
            Result? result = null;
            Error? err = null;

            var download_thread = new Thread<bool> ("sync-download-ua", () => {
                try {
                    result = manager.download (url, dest_path);
                } catch (Error e) {
                    err = e;
                }

                Idle.add (() => {
                    loop.quit ();
                    return false;
                });

                return true;
            });

            loop.run ();
            download_thread.join ();

            assert (err == null);
            assert (result != null);
            assert (result.is_downloaded);
            assert (received_user_agent == expected_user_agent);

            FileUtils.remove (dest_path);
            DirUtils.remove (temp_dir);
            server.disconnect ();
        }
    }
}
