#!/bin/bash
# Maps a screenshot number (as used in the fastlane image filenames, e.g.
# "6" for phoneScreenshots/6_en-US.png) to its integration test name (e.g.
# "HoldingHistoryPage"). Passed through unchanged if it's already a test name.
screenshot_name() {
    case "$1" in
        1) echo "ChartPage" ;;
        2) echo "PortfolioPage" ;;
        3) echo "SettingsPage" ;;
        4) echo "EditTickerPage" ;;
        5) echo "HoldingsPage" ;;
        6) echo "HoldingHistoryPage" ;;
        *) echo "$1" ;;
    esac
}
