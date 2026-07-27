namespace AppTests {
    using GLib;
    using ValaTux.Testcases;
    using ValaTux.Downloader;

    public class ExampleTest : BaseTest {
        construct {
            add_test ("manager/default_speed_limit", test_manager_default_speed_limit);
            add_test ("manager/set_speed_limit_bytes", test_manager_set_speed_limit_bytes);
            add_test ("manager/set_speed_limit_kilobytes", test_manager_set_speed_limit_kilobytes);
            add_test ("manager/set_speed_limit_megabytes", test_manager_set_speed_limit_megabytes);
            add_test ("manager/set_speed_limit_gigabytes", test_manager_set_speed_limit_gigabytes);
        }

        public void test_manager_default_speed_limit () {
            var manager = new Manager ();
            assert (manager.speed_limit_bps == 0);
        }

        public void test_manager_set_speed_limit_bytes () {
            var manager = new Manager ();
            manager.set_speed_limit_in_bytes (2048);
            assert (manager.speed_limit_bps == 2048);
        }

        public void test_manager_set_speed_limit_kilobytes () {
            var manager = new Manager ();
            manager.set_speed_limit_in_kilobytes (2);
            assert (manager.speed_limit_bps == 2 * 1024);
        }

        public void test_manager_set_speed_limit_megabytes () {
            var manager = new Manager ();
            manager.set_speed_limit_in_megabytes (3);
            assert (manager.speed_limit_bps == 3 * 1024 * 1024);
        }

        public void test_manager_set_speed_limit_gigabytes () {
            var manager = new Manager ();
            manager.set_speed_limit_in_gigabytes (1);
            assert (manager.speed_limit_bps == 1024 * 1024 * 1024);
        }

    }
}

