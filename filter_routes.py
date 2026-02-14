#!/usr/bin/env python3
"""Filter GTFS files to keep only specific routes"""

import os

# Routes to keep
KEEP_ROUTES = {'3048', '3144', '3175', '3164', '3165', '3166', '3180'}  # 4, 33, 16, N4, N5, N6, N7

GTFS_DIR = 'gtfs_extracted'
OUTPUT_DIR = 'assets/gtfs'

def filter_routes():
    """Filter routes.txt to keep only specified routes"""
    input_file = os.path.join(GTFS_DIR, 'routes.txt')
    output_file = os.path.join(OUTPUT_DIR, 'routes_filtered.txt')
    
    with open(input_file, 'r', encoding='utf-8-sig') as f_in:
        lines = f_in.readlines()
    
    if not lines:
        print("ERROR: routes.txt is empty")
        return
    
    # Write header
    filtered_lines = [lines[0]]
    
    # Filter routes
    for line in lines[1:]:
        if not line.strip():
            continue
        # Extract route_id (first field)
        fields = line.split(',')
        if fields:
            route_id = fields[0].strip('"').strip()
            if route_id in KEEP_ROUTES:
                filtered_lines.append(line)
    
    with open(output_file, 'w', encoding='utf-8', newline='') as f_out:
        f_out.writelines(filtered_lines)
    
    print(f"✓ Filtered routes.txt - kept {len(filtered_lines)-1} routes")

def filter_trips():
    """Filter trips.txt to keep only trips for specified routes"""
    input_file = os.path.join(GTFS_DIR, 'trips.txt')
    output_file = os.path.join(OUTPUT_DIR, 'trips_filtered.txt')
    
    kept_trips = set()
    
    with open(input_file, 'r', encoding='utf-8-sig') as f_in:
        lines = f_in.readlines()
    
    if not lines:
        print("ERROR: trips.txt is empty")
        return kept_trips
    
    # Write header
    filtered_lines = [lines[0]]
    
    # Filter trips
    for line in lines[1:]:
        if not line.strip():
            continue
        # Extract route_id (first field) and trip_id (third field)
        fields = line.split(',')
        if len(fields) >= 3:
            route_id = fields[0].strip('"').strip()
            trip_id = fields[2].strip('"').strip()
            if route_id in KEEP_ROUTES:
                filtered_lines.append(line)
                kept_trips.add(trip_id)
    
    with open(output_file, 'w', encoding='utf-8', newline='') as f_out:
        f_out.writelines(filtered_lines)
    
    print(f"✓ Filtered trips.txt - kept {len(filtered_lines)-1} trips")
    return kept_trips

def filter_stop_times(kept_trips):
    """Filter stop_times.txt to keep only stops for specified trips"""
    input_file = os.path.join(GTFS_DIR, 'stop_times.txt')
    output_file = os.path.join(OUTPUT_DIR, 'stop_times_filtered.txt')
    
    with open(input_file, 'r', encoding='utf-8-sig') as f_in:
        lines = f_in.readlines()
    
    if not lines:
        print("ERROR: stop_times.txt is empty")
        return
    
    # Write header  
    filtered_lines = [lines[0]]
    
    # Filter stop times
    for line in lines[1:]:
        if not line.strip():
            continue
        # Extract trip_id (first field)
        fields = line.split(',')
        if fields:
            trip_id = fields[0].strip('"').strip()
            if trip_id in kept_trips:
                filtered_lines.append(line)
    
    with open(output_file, 'w', encoding='utf-8', newline='') as f_out:
        f_out.writelines(filtered_lines)
    
    print(f"✓ Filtered stop_times.txt - kept {len(filtered_lines)-1} stop times")

def rename_filtered_files():
    """Rename filtered files to original names"""
    files_to_rename = ['routes', 'trips', 'stop_times']
    
    for filename in files_to_rename:
        filtered_file = os.path.join(OUTPUT_DIR, f'{filename}_filtered.txt')
        original_file = os.path.join(OUTPUT_DIR, f'{filename}.txt')
        
        if os.path.exists(filtered_file):
            if os.path.exists(original_file):
                os.remove(original_file)
            os.rename(filtered_file, original_file)
            print(f"✓ Renamed {filename}_filtered.txt to {filename}.txt")

if __name__ == '__main__':
    print("Filtering GTFS files to keep routes: 4, 33, 16, N4, N5, N6, N7")
    print("=" * 60)
    
    filter_routes()
    kept_trips = filter_trips()
    filter_stop_times(kept_trips)
    rename_filtered_files()
    
    print("=" * 60)
    print("✓ Done! GTFS files filtered successfully")
