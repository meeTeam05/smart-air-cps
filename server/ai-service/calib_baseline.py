class BaselineManager:
    def __init__(
        self,
        calibration_size=30,
        short_alpha=0.05,
        long_alpha=0.005,
        temp_gate=10,
        hum_gate=25,
        co_gate=5,
        no2_gate=80
    ):
        self.calibration_size = calibration_size

        self.short_alpha = short_alpha
        self.long_alpha = long_alpha

        self.temp_gate = temp_gate
        self.hum_gate = hum_gate
        self.co_gate = co_gate
        self.no2_gate = no2_gate

        self.buffer = []

        self.is_calibrated = False

        self.short_base = None
        self.long_base = None

        self.prev_sensor = None

    def add_calibration_sample(self, sensor):
        """
        sensor = {
            "temperature": ...,
            "humidity": ...,
            "co_ppm": ...,
            "no2_ppm": ...
        }
        """

        if self.is_calibrated:
            return

        self.buffer.append(sensor)

        if len(self.buffer) >= self.calibration_size:
            self.compute_initial_baseline()

    def compute_initial_baseline(self):
        temp = sum(x["temperature"] for x in self.buffer) / len(self.buffer)
        hum = sum(x["humidity"] for x in self.buffer) / len(self.buffer)
        co = sum(x["co_ppm"] for x in self.buffer) / len(self.buffer)
        no2 = sum(x["no2_ppm"] for x in self.buffer) / len(self.buffer)

        base = {
            "temp_base": temp,
            "hum_base": hum,
            "co_base": co,
            "no2_base": no2
        }

        self.short_base = base.copy()
        self.long_base = base.copy()

        self.is_calibrated = True

        print("\n===== BASELINE CALIBRATED =====")
        print(base)

    def get_delta(self, sensor, use_long=True):
        base = self.long_base if use_long else self.short_base

        return {
            "delta_temp": sensor["temperature"] - base["temp_base"],
            "delta_hum": sensor["humidity"] - base["hum_base"],
            "delta_co": sensor["co_ppm"] - base["co_base"],
            "delta_no2": sensor["no2_ppm"] - base["no2_base"],
        }

    def get_rate_change(self, sensor):
        if self.prev_sensor is None:
            return {
                "rate_temp": 0,
                "rate_hum": 0,
                "rate_co": 0,
                "rate_no2": 0,
            }

        return {
            "rate_temp": sensor["temperature"] - self.prev_sensor["temperature"],
            "rate_hum": sensor["humidity"] - self.prev_sensor["humidity"],
            "rate_co": sensor["co_ppm"] - self.prev_sensor["co_ppm"],
            "rate_no2": sensor["no2_ppm"] - self.prev_sensor["no2_ppm"],
        }

    def can_update_baseline(self, class_id, delta, rate):
        """
        Gating rule:
        Không cập nhật baseline khi nguy hiểm hoặc thay đổi quá mạnh.
        """

        if class_id == 3:
            return False

        if abs(delta["delta_temp"]) > self.temp_gate:
            return False

        if abs(delta["delta_hum"]) > self.hum_gate:
            return False

        if abs(delta["delta_co"]) > self.co_gate:
            return False

        if abs(delta["delta_no2"]) > self.no2_gate:
            return False

        if abs(rate["rate_temp"]) > 5:
            return False

        if abs(rate["rate_co"]) > 3:
            return False

        if abs(rate["rate_no2"]) > 50:
            return False

        return True

    def ema_update(self, old_value, current_value, alpha):
        return (1 - alpha) * old_value + alpha * current_value

    def update_baseline(self, sensor, class_id):
        delta = self.get_delta(sensor, use_long=True)
        rate = self.get_rate_change(sensor)

        allow_update = self.can_update_baseline(
            class_id=class_id,
            delta=delta,
            rate=rate
        )

        if allow_update:
            # short baseline cập nhật nhanh hơn
            self.short_base["temp_base"] = self.ema_update(
                self.short_base["temp_base"],
                sensor["temperature"],
                self.short_alpha
            )

            self.short_base["hum_base"] = self.ema_update(
                self.short_base["hum_base"],
                sensor["humidity"],
                self.short_alpha
            )

            self.short_base["co_base"] = self.ema_update(
                self.short_base["co_base"],
                sensor["co_ppm"],
                self.short_alpha
            )

            self.short_base["no2_base"] = self.ema_update(
                self.short_base["no2_base"],
                sensor["no2_ppm"],
                self.short_alpha
            )

            # long baseline cập nhật chậm hơn
            self.long_base["temp_base"] = self.ema_update(
                self.long_base["temp_base"],
                sensor["temperature"],
                self.long_alpha
            )

            self.long_base["hum_base"] = self.ema_update(
                self.long_base["hum_base"],
                sensor["humidity"],
                self.long_alpha
            )

            self.long_base["co_base"] = self.ema_update(
                self.long_base["co_base"],
                sensor["co_ppm"],
                self.long_alpha
            )

            self.long_base["no2_base"] = self.ema_update(
                self.long_base["no2_base"],
                sensor["no2_ppm"],
                self.long_alpha
            )

        self.prev_sensor = sensor.copy()

        return allow_update

    def make_feature_vector(self, sensor):
        delta = self.get_delta(sensor, use_long=True)

        features = {
            "temperature": sensor["temperature"],
            "humidity": sensor["humidity"],
            "co_ppm": sensor["co_ppm"],
            "no2_ppm": sensor["no2_ppm"],

            "temp_base": self.long_base["temp_base"],
            "hum_base": self.long_base["hum_base"],
            "co_base": self.long_base["co_base"],
            "no2_base": self.long_base["no2_base"],

            "delta_temp": delta["delta_temp"],
            "delta_hum": delta["delta_hum"],
            "delta_co": delta["delta_co"],
            "delta_no2": delta["delta_no2"],
        }

        return features

    def print_baseline(self):
        print("\nShort baseline:", self.short_base)
        print("Long baseline :", self.long_base)