namespace ValaTux.Downloader {
    const int64 KILOBYTE = 1024;
    const int64 MEGABYTE = 1024 * 1024;
    const int64 GIGABYTE = 1024 * 1024 * 1024;
    const int64 TERABYTE = 1024 * 1024 * 1024 * 1024;

    const int64 TIME_SECOND = 1;
    const int64 TIME_MINUTE = 60;
    const int64 TIME_HOUR = 3600;
    const int64 TIME_DAY = 86400;
    const int64 TIME_WEEK = 604800;
    const int64 TIME_MONTH = 2592000;
    const int64 TIME_YEAR = 31536000;

    public delegate void DownloadProgressCallback (
        int64 downloaded_bytes,
        int64 content_length,
        int64 actual_speed_bps,
        int64 remaining_time
    );

    public async void async_sleep (uint interval_ms) {
        Timeout.add (interval_ms, () => {
            async_sleep.callback ();
            return false;
        });
        yield;
    }
}
