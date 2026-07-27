namespace AppTests {
    using GLib;
    using ValaTux.Downloader;
    using ValaTux.Testcases;

    public class DownloadSyncInternalErrorTest : BaseTest {
        construct {
            add_test ("manager/download_sync_internal_error_unknown_length_result_state", test_manager_download_sync_internal_error_unknown_length_result_state);
        }

        public void test_manager_download_sync_internal_error_unknown_length_result_state () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);

            server.add_handler (null, (srv, msg, path, query) => {
                msg.set_status (Soup.Status.INTERNAL_SERVER_ERROR, null);
            });

            try {
                assert (server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY));
            } catch (Error e) {
                assert_not_reached ();
            }

            var uris = server.get_uris ();
            string base_uri = uris.nth_data (0).to_string ();
            string url = base_uri.has_suffix ("/") ? @"$(base_uri)server-error" : @"$(base_uri)/server-error";

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string dest_path = Path.build_filename (temp_dir, "downloaded-server-error.txt");
            var manager = new Manager ();
            var loop = new MainLoop (null, false);

            Result? result = null;
            Error? err = null;

            var download_thread = new Thread<bool> ("sync-download-server-error", () => {
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
            assert (!result.is_downloaded);
            assert (result.status_code == Soup.Status.INTERNAL_SERVER_ERROR);
            assert (result.actual_speed_bps == 0);
            assert (result.remaining_time == -1);

            FileUtils.remove (dest_path);
            DirUtils.remove (temp_dir);
            server.disconnect ();
        }
    }
}
