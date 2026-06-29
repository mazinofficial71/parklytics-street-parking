from flask import Flask, jsonify, request
import pandas as pd
from datetime import datetime
import os

from utils.data_cleaning import filter_outliers
from utils.occupancy_update import LIVE_STATE, update_availability_status, calculate_confidence
from utils.parking_events import handle_event, handle_feedback
from config import CSV_PATH, DEMO_DATETIME

app = Flask(__name__)

# Load parking history data once at startup for fast responses
df = pd.read_csv(CSV_PATH)
df['timestamp'] = pd.to_datetime(df['timestamp'])


@app.route('/')
def home():
    return "Parklytics Backend is Alive!"


@app.route('/parking-event', methods=['POST'])
def receive_parking_event():
    """Receives crowdsourced parking events from mobile clients."""
    return handle_event(request.json)


@app.route('/submit-feedback', methods=['POST'])
def receive_feedback():
    """Receives user feedback on parking availability."""
    return handle_feedback(request.json)


@app.route('/get-current-status')
def get_current_status():
    """
    Returns real-time parking status for all road segments.
    Combines historical ML predictions with live crowdsourced events.
    """
    # In production, use datetime.now(); demo uses a fixed timestamp
    current_time = DEMO_DATETIME
    current_data = df[df['timestamp'] == current_time]

    if current_data.empty:
        return jsonify({"error": "No data found for this time"}), 404

    result = []
    for _, row in current_data.iterrows():
        road = row['road_name']
        base_occ = row['occupied_spots']
        capacity = row['total_capacity']

        # Apply live crowdsourced overrides
        live_added = LIVE_STATE.get(road, {}).get('live_spots_added', 0)

        # Filter outliers and compute final occupancy
        final_occ = filter_outliers(base_occ + live_added, capacity)
        percent = final_occ / capacity if capacity > 0 else 0
        status = update_availability_status(percent)

        # Confidence: 0.7 weight on historical, 0.3 on live signal
        live_signal = 1.0 if live_added > 0 else 0.0
        confidence = calculate_confidence(0.8, live_signal)

        result.append({
            'road_name': road,
            'occupied_spots': final_occ,
            'total_capacity': capacity,
            'status': status,
            'confidence': confidence
        })

    return jsonify(result)


if __name__ == '__main__':
    # host='0.0.0.0' allows mobile devices on the same WiFi to connect
    app.run(host='0.0.0.0', port=5000, debug=True)
