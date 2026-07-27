namespace AppTests {
    using GLib;
    using ValaTux.Downloader;
    using ValaTux.Testcases;

    public class DownloadSyncLocalServerTest : BaseTest {
        construct {
            add_test ("manager/download_sync_local_server", test_manager_download_sync_local_server);
        }

        public void test_manager_download_sync_local_server () {
            var server = new Soup.Server ("server-header", "ValaTestServer", null);
            string expected = "Downloader sync payload";
            uint8[] response_body = expected.data;

            server.add_handler (null, (srv, msg, path, query) => {
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
            string url = base_uri.has_suffix ("/") ? @"$(base_uri)download-sync" : @"$(base_uri)/download-sync";

            string temp_dir;
            try {
                temp_dir = DirUtils.make_tmp ("vala-downloader-lib-test-XXXXXX");
            } catch (FileError e) {
                assert_not_reached ();
            }

            string dest_path = Path.build_filename (temp_dir, "downloaded-sync.txt");
            var manager = new Manager ();
            var loop = new MainLoop (null, false);

            Result? result = null;
            Error? err = null;

            var download_thread = new Thread<bool> ("sync-download", () => {
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
            assert (result.status_code == Soup.Status.OK);
            assert (result.remaining_time == 0);
            assert (result.actual_speed_bps > 0);

            string downloaded;
            try {
                FileUtils.get_contents (dest_path, out downloaded);
            } catch (FileError e) {
                assert_not_reached ();
            }

            assert (downloaded == expected);

            FileUtils.remove (dest_path);
            DirUtils.remove (temp_dir);
            server.disconnect ();
        }
    }
}
