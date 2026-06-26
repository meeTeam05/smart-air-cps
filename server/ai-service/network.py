from sklearn.tree import DecisionTreeClassifier
from sklearn.ensemble import RandomForestClassifier

FEATURE_COLS = [
    "temperature", "humidity", "co_ppm", "no2_ppm",
    "temp_base", "hum_base", "co_base", "no2_base",
    "delta_temp", "delta_hum", "delta_co", "delta_no2"
]

LABEL_COL = "label"

CLASS_MAPPING = {
    0: {"fan": 0, "light": 0, "buzzer": 0, "meaning": "Normal"},
    1: {"fan": 0, "light": 1, "buzzer": 1, "meaning": "Gas warning"},
    2: {"fan": 1, "light": 1, "buzzer": 0, "meaning": "Cooling / ventilation"},
    3: {"fan": 1, "light": 1, "buzzer": 1, "meaning": "Danger"},
}


def build_decision_tree():
    return DecisionTreeClassifier(
        criterion="gini",
        max_depth=8,
        min_samples_split=30,
        min_samples_leaf=15,
        class_weight="balanced",
        random_state=42,
    )


def build_random_forest():
    return RandomForestClassifier(
        n_estimators=120,
        max_depth=10,
        min_samples_split=30,
        min_samples_leaf=15,
        class_weight="balanced",
        random_state=42,
        n_jobs=-1,
    )


def decode_class(class_id):
    result = CLASS_MAPPING.get(int(class_id))
    if result is None:
        raise ValueError(f"unknown class_id: {class_id}")
    return result
