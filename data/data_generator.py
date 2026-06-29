"""
Generates 30 days of synthetic parking occupancy data
based on realistic time-of-day and weekend patterns.
Output: data/parking_history.csv and data/human_view_parking.csv
"""
import pandas as pd
import random
from datetime import timedelta

from config import ROADS, DAYS_OF_HISTORY, START_DATE


def get_occupancy_params(hour, is_weekend):
    """Returns base occupancy rate and noise limit for a given hour."""
    base_occupancy = 0.15
    variation_limit = 0.05

    if 1 <= hour < 5:        # Quiet night
        base_occupancy, variation_limit = 0.08, 0.04
    elif 8 <= hour < 10:     # Morning rush
        base_occupancy, variation_limit = 0.35, 0.10
    elif 12 <= hour < 15:    # Lunch / midday
        base_occupancy, variation_limit = 0.50, 0.10
    elif 17 <= hour < 20:    # Beach peak — sunset crowd
        base_occupancy, variation_limit = 0.95, 0.03

    if is_weekend:
        base_occupancy += 0.05 if 1 <= hour < 5 else 0.15

    return base_occupancy, variation_limit


def generate_data():
    """Generates parking data and saves to CSV files."""
    data = []
    total_segments = DAYS_OF_HISTORY * 48

    print(f"Generating data for {total_segments} time segments across {len(ROADS)} roads...")

    for i in range(total_segments):
        current_time = START_DATE + timedelta(minutes=30 * i)
        hour = current_time.hour
        is_weekend = current_time.weekday() >= 5
        base_occupancy, variation_limit = get_occupancy_params(hour, is_weekend)

        for road_name, capacity in ROADS.items():
            noise = random.uniform(-variation_limit, variation_limit)
            final_percent = max(0.0, min(1.0, base_occupancy + noise))
            occupied = int(capacity * final_percent)

            if base_occupancy > 0.05 and occupied == 0:
                occupied = random.randint(1, 3)

            status = "High" if final_percent > 0.8 else "Med" if final_percent > 0.4 else "Low"

            data.append({
                "timestamp": current_time,
                "road_name": road_name,
                "occupied_spots": occupied,
                "total_capacity": capacity,
                "status": status
            })

    df = pd.DataFrame(data)
    df.to_csv("data/parking_history.csv", index=False)

    # Human-readable pivot table
    human_view = df.pivot(index="timestamp", columns="road_name", values="occupied_spots")
    human_view.to_csv("data/human_view_parking.csv")

    print("SUCCESS: parking_history.csv and human_view_parking.csv saved to data/")


if __name__ == "__main__":
    generate_data()
