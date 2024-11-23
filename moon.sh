#!/usr/bin/env bash

COINGECKO_API_KEY_MOON="CG-rQB1NGbc1dVSrQTZYHWuVw31"
NOTIFICATION_THRESHOLD_PERCENT=0.5
LOG_FILE="./moon.log"
RATE_LIMIT_DELAY=30  # Minimum seconds between requests (20 requests per minute = 1 request per 3 seconds)

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" >> "$LOG_FILE"
    echo "ERROR: $1" >&2
}

log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] INFO: $1" >> "$LOG_FILE"
    echo "INFO: $1"
}

print_price() {
    local price=$1
    local difference=$2
    local significant=$3
    
    if (( $(echo "$difference > 0" | bc -l) )); then
        echo -e "${GREEN}Bitcoin: \$$price (↑$difference%)${NC}"
        if [ "$significant" = "true" ]; then
            say "Bitcoin is now $price dollars"
        fi
    elif (( $(echo "$difference < 0" | bc -l) )); then
        echo -e "${RED}Bitcoin: \$$price (↓$difference%)${NC}"
        if [ "$significant" = "true" ]; then
            say "Bitcoin is now $price dollars"
        fi
    else
        echo -e "${GRAY}Bitcoin: \$$price${NC}"
    fi
}

check_bitcoin_price() {
    # Get current Bitcoin price from CoinGecko API with timestamp to prevent caching
    timestamp=$(date +%s)
    api_response=$(curl -s -H "X-CG-API-Key: $COINGECKO_API_KEY_MOON" \
        "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&t=$timestamp")

    # Check if API request failed
    if [ -z "$api_response" ]; then
        log_error "Empty response from API"
        return 1
    fi

    log_info "API Response: $api_response"

    if ! current_price=$(echo "$api_response" | jq -r '.bitcoin.usd'); then
        log_error "Failed to parse price from API response"
        return 1
    fi

    # Check if jq returned null
    if [ "$current_price" = "null" ]; then
        log_error "API returned null price"
        return 1
    fi

    log_info "Current price: $current_price"

    # Handle price file
    PRICE_FILE="./moon_current_price_btc"

    # Read the previous price if file exists and is not empty
    if [ -f "$PRICE_FILE" ] && [ -s "$PRICE_FILE" ]; then
        previous_price=$(cat "$PRICE_FILE")
        if ! [[ "$previous_price" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            log_info "Invalid previous price in file. Starting fresh."
            previous_price="$current_price"
            echo "$current_price" > "$PRICE_FILE"
        fi
    else
        log_info "No previous price found. Starting fresh."
        previous_price="$current_price"
        echo "$current_price" > "$PRICE_FILE"
    fi

    log_info "Previous price: $previous_price"

    # Calculate price difference percentage with higher precision
    if ! difference=$(echo "scale=4; (($current_price - $previous_price) / $previous_price) * 100" | bc 2>/dev/null); then
        log_error "Failed to calculate price difference"
        return 1
    fi
    # Round to 2 decimal places for display
    difference=$(printf "%.2f" "$difference")
    log_info "Price difference: $difference%"

    difference_abs=$(echo "$difference" | tr -d -)
    log_info "Absolute difference: $difference_abs%"

    # Check if difference exceeds threshold
    if (( $(echo "$difference_abs >= $NOTIFICATION_THRESHOLD_PERCENT" | bc -l) )); then
        log_info "Threshold exceeded. Difference: $difference%"
        # Print price with color and say it (passing true for significant change)
        print_price "$current_price" "$difference" "true"
        
        # Save new price only when threshold is exceeded
        echo "$current_price" > "$PRICE_FILE"
        log_info "Saved new price: $current_price"
    else
        log_info "No significant change. Current price: $current_price"
        # Just print the current price in gray (passing false for significant change)
        print_price "$current_price" "$difference" "false"
    fi

    return 0
}

# Trap Ctrl+C and clean up
trap 'echo -e "\nExiting..."; exit 0' INT

# Main loop
echo "Starting Bitcoin price monitor. Press Ctrl+C to exit."
while true; do
    check_bitcoin_price
    sleep $RATE_LIMIT_DELAY
done
