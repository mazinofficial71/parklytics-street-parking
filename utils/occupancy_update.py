# Stores live crowdsourced events that overlay historical predictions
# Format: { road_name: { 'live_spots_added': int, 'last_event_time': datetime } }
LIVE_STATE = {}


def update_availability_status(percent):
    """
    Returns availability status based on occupancy percentage.
    - Available : < 50%
    - Filling   : 50% - 80%
    - Full      : > 80%
    """
    if percent < 0.5:
        return "Available"
    elif percent <= 0.8:
        return "Filling"
    else:
        return "Full"


def calculate_confidence(historical_prob, live_signal):
    """
    Calculates a confidence score blending historical and live signals.
    Formula: confidence = 0.7 * historical_probability + 0.3 * live_event_signal
    """
    hist = max(0.0, min(1.0, historical_prob))
    live = max(0.0, min(1.0, live_signal))
    confidence = (0.7 * hist) + (0.3 * live)
    return round(confidence, 2)
