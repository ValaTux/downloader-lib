namespace ValaTux.Downloader {
    public class Result : Object {
        public bool is_downloaded { get; set; default = false; }
        public int64 actual_speed_bps { get; set; default = 0; }
        public int64 remaining_time { get; set; default = -1; }
        public uint status_code { get; set; default = 0; }

        public int64 get_remaining_time_in_seconds () {
            return this.remaining_time;
        }

        public int64 get_remaining_time_in_minutes () {
            if (this.remaining_time < 0) {
                return -1;
            }
            return this.remaining_time / ValaTux.Downloader.TIME_MINUTE;
        }

        public int64 get_remaining_time_in_hours () {
            if (this.remaining_time < 0) {
                return -1;
            }
            return this.remaining_time / ValaTux.Downloader.TIME_HOUR;
        }

        public int64 get_remaining_time_in_days () {
            if (this.remaining_time < 0) {
                return -1;
            }
            return this.remaining_time / ValaTux.Downloader.TIME_DAY;
        }

        public int64 get_actual_speed_in_kilobytes () {
            return this.actual_speed_bps / ValaTux.Downloader.KILOBYTE;
        }

        public int64 get_actual_speed_in_megabytes () {
            return this.actual_speed_bps / ValaTux.Downloader.MEGABYTE;
        }

        public int64 get_actual_speed_in_gigabytes () {
            return this.actual_speed_bps / ValaTux.Downloader.GIGABYTE;
        }

    }
}
