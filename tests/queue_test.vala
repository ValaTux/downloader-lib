namespace AppTests {
    using GLib;
    using ValaTux.Downloader;
    using ValaTux.Testcases;

    public class QueueTest : BaseTest {
        construct {
            add_test ("manager/download_queue_sync_mixed_results", test_manager_download_queue_sync_mixed_results);
            add_test ("manager/download_queue_async_mixed_results", test_manager_download_queue_async_mixed_results);
        }

        public void test_manager_download_queue_sync_mixed_results () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);
            string ok_payload = "Downloader batch sync payload";
            uint8[] ok_response_body = ok_payload.data;

            server.add_handler (null, (srv, msg, path, query) => {
                if (path == "/ok-sync") {
                    msg.set_status (Soup.Status.OK, null);
                    msg.set_response ("text/plain", Soup.MemoryUse.COPY, ok_response_body);
                } else {
                    msg.set_status (Soup.Status.NOT_FOUND, null);
                }
            });

            try {
                assert (server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY));
            } catch (Error e) {
                assert_not_reached ();
            }

            var uris = server.get_uris ();
            string base_uri = uris.nth_data (0).to_string ();

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string ok_url = base_uri.has_suffix ("/") ? @"$(base_uri)ok-sync" : @"$(base_uri)/ok-sync";
            string missing_url = base_uri.has_suffix ("/") ? @"$(base_uri)missing-sync" : @"$(base_uri)/missing-sync";

            string ok_dest_path = Path.build_filename (temp_dir, "downloaded-batch-sync-ok.txt");
            string missing_dest_path = Path.build_filename (temp_dir, "downloaded-batch-sync-missing.txt");

            var manager = new Manager ();
            var queued_ok = manager.add_to_download (ok_url, ok_dest_path);
            var queued_missing = manager.add_to_download (missing_url, missing_dest_path);

            var loop = new MainLoop (null, false);
            Gee.ArrayList<BatchDownloadResult>? results = null;

            var download_thread = new Thread<bool> ("sync-download-queue", () => {
                results = manager.download_queued ();

                Idle.add (() => {
                    loop.quit ();
                    return false;
                });

                return true;
            });

            loop.run ();
            download_thread.join ();

            assert (results != null);
            assert (results.size == 2);
            assert (results[0] == queued_ok);
            assert (results[1] == queued_missing);

            var ok_result = results[0];
            assert (ok_result.error_message == null);
            assert (ok_result.result != null);
            assert (ok_result.result.is_downloaded);
            assert (ok_result.result.status_code == Soup.Status.OK);

            var missing_result = results[1];
            assert (missing_result.error_message == null);
            assert (missing_result.result != null);
            assert (!missing_result.result.is_downloaded);
            assert (missing_result.result.status_code == Soup.Status.NOT_FOUND);

            string downloaded;
            try {
                FileUtils.get_contents (ok_dest_path, out downloaded);
            } catch (FileError e) {
                assert_not_reached ();
            }

            assert (downloaded == ok_payload);

            FileUtils.remove (ok_dest_path);
            FileUtils.remove (missing_dest_path);
            DirUtils.remove (temp_dir);
            server.disconnect ();
        }

        public void test_manager_download_queue_async_mixed_results () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);
            string ok_payload = "Downloader batch async payload";
            uint8[] ok_response_body = ok_payload.data;

            server.add_handler (null, (srv, msg, path, query) => {
                if (path == "/ok-async") {
                    msg.set_status (Soup.Status.OK, null);
                    msg.set_response ("text/plain", Soup.MemoryUse.COPY, ok_response_body);
                } else {
                    msg.set_status (Soup.Status.NOT_FOUND, null);
                }
            });

            try {
                assert (server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY));
            } catch (Error e) {
                assert_not_reached ();
            }

            var uris = server.get_uris ();
            string base_uri = uris.nth_data (0).to_string ();

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string ok_url = base_uri.has_suffix ("/") ? @"$(base_uri)ok-async" : @"$(base_uri)/ok-async";
            string missing_url = base_uri.has_suffix ("/") ? @"$(base_uri)missing-async" : @"$(base_uri)/missing-async";

            string ok_dest_path = Path.build_filename (temp_dir, "downloaded-batch-async-ok.txt");
            string missing_dest_path = Path.build_filename (temp_dir, "downloaded-batch-async-missing.txt");

            var manager = new Manager ();
            var queued_ok = manager.add_to_download (ok_url, ok_dest_path);
            var queued_missing = manager.add_to_download (missing_url, missing_dest_path);

            var loop = new MainLoop (null, false);

            Gee.ArrayList<BatchDownloadResult>? results = null;

            manager.download_queued_async.begin (true, (obj, res) => {
                results = manager.download_queued_async.end (res);
                loop.quit ();
            });

            loop.run ();

            assert (results != null);
            assert (results.size == 2);
            assert (results[0] == queued_ok);
            assert (results[1] == queued_missing);

            var ok_result = results[0];
            assert (ok_result.error_message == null);
            assert (ok_result.result != null);
            assert (ok_result.result.is_downloaded);
            assert (ok_result.result.status_code == Soup.Status.OK);

            var missing_result = results[1];
            assert (missing_result.error_message == null);
            assert (missing_result.result != null);
            assert (!missing_result.result.is_downloaded);
            assert (missing_result.result.status_code == Soup.Status.NOT_FOUND);

            string downloaded;
            try {
                FileUtils.get_contents (ok_dest_path, out downloaded);
            } catch (FileError e) {
                assert_not_reached ();
            }

            assert (downloaded == ok_payload);

            FileUtils.remove (ok_dest_path);
            FileUtils.remove (missing_dest_path);
            DirUtils.remove (temp_dir);
            server.disconnect ();
        }
    }
}
