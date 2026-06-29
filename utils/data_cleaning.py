import pandas as pd


def filter_outliers(occupied_spots, total_capacity):
    """
    Ensures occupied spots stay within valid bounds: 0 <= occupied <= total_capacity.
    """
    return max(0, min(total_capacity, occupied_spots))


def apply_iqr_filtering(df, column_name='occupied_spots'):
    """
    Applies IQR statistical filtering to remove abnormal occupancy spikes
    from historical data. Returns the filtered DataFrame.
    """
    if df.empty or column_name not in df.columns:
        return df

    Q1 = df[column_name].quantile(0.25)
    Q3 = df[column_name].quantile(0.75)
    IQR = Q3 - Q1

    lower_bound = Q1 - 1.5 * IQR
    upper_bound = Q3 + 1.5 * IQR

    filtered_df = df[
        (df[column_name] >= lower_bound) &
        (df[column_name] <= upper_bound)
    ]
    return filtered_df
