"""
End-to-end pipeline test for the Parklytics backend.
Tests: status fetch → event ingestion → status update verification.
Run with the Flask server active: python server.py
"""
import requests
import json

BASE_URL = "http://127.0.0.1:5000"


def test_pipeline():
    print("=" * 50)
    print("PARKLYTICS PIPELINE TEST")
    print("=" * 50)

    # Step 1: Fetch status before event
    print("\n[1] Fetching status BEFORE parking event...")
    try:
        resp = requests.get(f"{BASE_URL}/get-current-status")
        if resp.status_code == 200:
            data = resp.json()
            mbr = next((d for d in data if d['road_name'] == 'Main Beach Road'), None)
            print("Main Beach Road — BEFORE:")
            print(json.dumps(mbr, indent=2))
        else:
            print(f"Error: {resp.status_code}")
    except requests.exceptions.ConnectionError:
        print("ERROR: Cannot connect to server. Start it with: python server.py")
        return

    # Step 2: Send crowdsourced parking event
    print("\n[2] Sending crowdsourced parking event...")
    event_payload = {
        "event": "parking_detected",
        "lat": 11.2648,
        "lng": 75.7681,
        "timestamp": "2026-03-14T23:55:00Z"
    }
    resp = requests.post(f"{BASE_URL}/parking-event", json=event_payload)
    print(f"Response [{resp.status_code}]: {resp.json()}")

    # Step 3: Verify status updated
    print("\n[3] Fetching status AFTER parking event...")
    resp = requests.get(f"{BASE_URL}/get-current-status")
    if resp.status_code == 200:
        data = resp.json()
        mbr = next((d for d in data if d['road_name'] == 'Main Beach Road'), None)
        print("Main Beach Road — AFTER:")
        print(json.dumps(mbr, indent=2))
        print("\nExpected: occupied_spots +1, confidence = 0.86")

    print("\n" + "=" * 50)
    print("Test complete.")
    print("=" * 50)


if __name__ == "__main__":
    test_pipeline()
