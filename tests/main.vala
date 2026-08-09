using GLib;
using Gee;

int main (string[] args) {

    ValaTux.Testcases.BaseTest.saved_commands = new Gee.ArrayList<ValaTux.Testcases.TestCommand> ();
    Test.init (ref args);

    ValaTux.Testcases.register_test_suite<AppTests.ExampleTest> ();
    ValaTux.Testcases.register_test_suite<AppTests.DownloadAsyncLocalServerTest> ();
    ValaTux.Testcases.register_test_suite<AppTests.DownloadFeaturesTest> ();
    ValaTux.Testcases.register_test_suite<AppTests.DownloadSyncLocalServerTest> ();
    ValaTux.Testcases.register_test_suite<AppTests.DownloadSyncNotFoundTest> ();
    ValaTux.Testcases.register_test_suite<AppTests.DownloadSyncInternalErrorTest> ();
    ValaTux.Testcases.register_test_suite<AppTests.QueueTest> ();


    return Test.run ();
}

