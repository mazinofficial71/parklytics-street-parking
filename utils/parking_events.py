import csv
import math
import os
from datetime import datetime

from utils.occupancy_update import LIVE_STATE
from config import ROAD_SEGMENTS, LOG_FILE, FEEDBACK_LOG_FILE


def initialize_log_file(filepath, headers):
    """Create a CSV log file with headers if it doesn't exist."""
    if not os.path.exists(filepath):
        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(headers)


def log_event(timestamp, lat, lng, event_type, road_name):
    """Appends a parking event to the event CSV log."""
    initialize_log_file(LOG_FILE, ['timestamp', 'lat', 'lng', 'event_type', 'road_name'])
    with open(LOG_FILE, 'a', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([timestamp, lat, lng, event_type, road_name])


def log_feedback(timestamp, road_name, found_easily):
    """Appends user feedback to the feedback CSV log."""
    initialize_log_file(FEEDBACK_LOG_FILE, ['timestamp', 'road_name', 'found_easily'])
    with open(FEEDBACK_LOG_FILE, 'a', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([timestamp, road_name, found_easily])


def get_distance(lat1, lon1, lat2, lon2):
    """
    Returns the distance in km between two GPS coordinates using the Haversine formula.
    """
    R = 6371
    dLat = math.radians(lat2 - lat1)
    dLon = math.radians(lon2 - lon1)
    a = (math.sin(dLat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dLon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def map_to_nearest_road(lat, lng):
    """
    Maps a GPS coordinate to the nearest road segment using Haversine distance.
    """
    min_dist = float('inf')
    nearest_road = None

    for road_name, points in ROAD_SEGMENTS.items():
        for point in points:
            dist = get_distance(lat, lng, point[0], point[1])
            if dist < min_dist:
                min_dist = dist
                nearest_road = road_name

    return nearest_road


def handle_event(data):
    """
    Processes incoming crowdsourced parking events from mobile clients.
    Validates input, maps GPS to road, updates LIVE_STATE, and logs.
    """
    event_type = data.get('event')
    lat = data.get('lat')
    lng = data.get('lng')
    timestamp_str = data.get('timestamp')

    if not all([event_type, lat, lng, timestamp_str]):
        return {"error": "Missing required fields"}, 400

    try:
        lat = float(lat)
        lng = float(lng)
        event_time = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
    except ValueError:
        return {"error": "Invalid format for lat/lng or timestamp"}, 400

    nearest_road = map_to_nearest_road(lat, lng)
    if nearest_road is None:
        return {"error": "Location too far from mapped roads"}, 404

    log_event(timestamp_str, lat, lng, event_type, nearest_road)

    if event_type in ["parking_detected", "bluetooth_disconnect"]:
        if nearest_road not in LIVE_STATE:
            LIVE_STATE[nearest_road] = {'live_spots_added': 0, 'last_event_time': None}
        LIVE_STATE[nearest_road]['live_spots_added'] += 1
        LIVE_STATE[nearest_road]['last_event_time'] = event_time

    return {
        "message": "Event processed",
        "mapped_road": nearest_road,
        "recorded_event": event_type
    }, 200


def handle_feedback(data):
    """
    Processes user feedback to adjust live occupancy predictions.
    """
    road_name = data.get('road_name')
    found_easily = data.get('found_easily')

    if not road_name or found_easily is None:
        return {"error": "Missing fields"}, 400

    log_feedback(datetime.now().isoformat(), road_name, found_easily)

    if road_name not in LIVE_STATE:
        LIVE_STATE[road_name] = {'live_spots_added': 0, 'last_event_time': datetime.now()}

    # Adjust predictions based on feedback
    if not found_easily:
        LIVE_STATE[road_name]['live_spots_added'] += 3  # penalize
    else:
        LIVE_STATE[road_name]['live_spots_added'] -= 1  # reward

    LIVE_STATE[road_name]['last_event_time'] = datetime.now()
    return {"message": "Feedback recorded and predictions updated!"}, 200
