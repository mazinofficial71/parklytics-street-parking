import os
from datetime import datetime

# --- Paths ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(BASE_DIR, 'data', 'parking_history.csv')
LOG_FILE = os.path.join(BASE_DIR, 'data', 'parking_events.csv')
FEEDBACK_LOG_FILE = os.path.join(BASE_DIR, 'data', 'parking_feedback.csv')

# --- Roads & Capacities ---
ROADS = {
    "Main Beach Road": 80,
    "Joseph Road": 20,
    "Customs Road": 25,
    "Red Cross Road": 30,
    "Unnamed Alley (Rafi Rd)": 8
}

# --- Road GPS Segments ---
ROAD_SEGMENTS = {
    "Main Beach Road": [(11.2648, 75.7681), (11.2478, 75.7728)],
    "Joseph Road": [(11.2587, 75.7707), (11.2588, 75.7785)],
    "Customs Road": [(11.2561, 75.7714), (11.2562, 75.7795)],
    "Red Cross Road": [(11.2541, 75.7722), (11.2542, 75.7820)],
    "Unnamed Alley (Rafi Rd)": [(11.2550, 75.7730), (11.2555, 75.7745)]
}

# --- Data Generation ---
DAYS_OF_HISTORY = 30
START_DATE = datetime(2026, 1, 1)

# --- Demo / Testing ---
DEMO_DATETIME = datetime(2026, 1, 1, 18, 0, 0)  # Fixed time for demo mode

# --- Analysis Output ---
OUTPUT_DIR = os.path.join(BASE_DIR, 'analysis', 'graphs')
