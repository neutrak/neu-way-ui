#!/bin/bash

#if any instances of waybar are already running, stop those first
killall waybar

waybar -c "$HOME"/.config/custom-themes/neu-way-ui/config/waybar/config &
waybar -c "$HOME"/.config/custom-themes/neu-way-ui/config/waybar/config-bottom &

