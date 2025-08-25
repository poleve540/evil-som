#!/bin/bash

./province_map_generator.py map.png
./province_centers.py provinces.png
./province_neighbors.py provinces.png
