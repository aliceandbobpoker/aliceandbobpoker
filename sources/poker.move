module aliceandbobpoker::poker {
    use std::vector;
    use std::debug;

    const HAND_HIGH_CARD: u8 = 0;
    const HAND_PAIR: u8 = 1;
    const HAND_TWO_PAIR: u8 = 2;
    const HAND_THREE_OF_A_KIND: u8 = 3;
    const HAND_STRAIGHT: u8 = 4;
    const HAND_FLUSH: u8 = 5;
    const HAND_FULL_HOUSE: u8 = 6;
    const HAND_FOUR_OF_A_KIND: u8 = 7;
    const HAND_STRAIGHT_FLUSH: u8 = 8;

    const HAND_BETTER: u8 = 1;
    const HAND_WORSE: u8 = 0;
    const HAND_EQUAL: u8 = 2;

    struct Hand has drop {
        key: vector<u64>,
        card_bits: u64,
        hand_type: u8,
        player_idx: u8,
    }

    public fun get_counts(card_bits: u64): vector<u64> {
        let counts: vector<u64> = vector<u64>[8191,0,0,0,0];
        let i = 1;
        while (i < 5) {
            let j = i;
            while (j > 0) {
                let curr = card_bits & 8191;
                let curr_count = *vector::borrow(&counts, j - 1);
                let anded = curr & curr_count;
                let new_count1 = curr_count - anded;
                let new_count2 = *vector::borrow(&counts, j) + anded;
                vector::push_back(&mut counts, new_count1);
                vector::swap_remove(&mut counts, j - 1);
                vector::push_back(&mut counts, new_count2);
                vector::swap_remove(&mut counts, j);
                j = j - 1;
            };
            // debug::print(&counts);
            card_bits = card_bits >> 13;
            i = i + 1;
        };
        counts
    }

    public fun get_straight_flush(card_bits: u64): u8 {
        let i = 0;
        while (i < 4) {
            let curr = card_bits & 8191;
            let straight = get_straight(curr);
            if (straight > 0) {
                return straight
            };
            card_bits = card_bits >> 13;
            i = i + 1;
        };
        0u8
    }

    public fun get_straight(ranks: u64): u8 {
        let so_far = 0;
        let i = 0;
        let has_ace = ranks & 1;
        while (i < 13) {
            let curr_bit = ranks & 1;
            if (curr_bit == 1) {
                so_far = so_far + 1;
                if (so_far == 5) {
                    return ((14 - i) as u8)
                };
            } else {    
                so_far = 0;
            };
            ranks = ranks >> 1;
            i = i + 1;
        };
        if (so_far == 4 && has_ace == 1) {
            return 1u8
        };
        0u8
    }

    public fun get_flush(card_bits: u64): u64 {
        let i = 0;
        while (i < 4) {
            // let found: vector<u8> = vector::empty();
            let found = 0u64;
            let num_found = 0;
            let j = 0;
            let curr = card_bits & 8191;
            let power = 1 << 12;
            while (j < 13) {
                let curr_bit = curr & 1;
                if (curr_bit == 1) {
                    num_found = num_found + 1;
                    // vector::push_back(&mut found, (j as u8));
                    found = found + power;
                    if (num_found == 5) {
                        return found
                        // found flush
                    };
                };
                curr = curr >> 1;
                j = j + 1;
                power = power >> 1;
            };
            card_bits = card_bits >> 13;
            i = i + 1;
        };
        // vector::empty()
        0u64
    }

    public fun parse_n_bits(ranks: u64, num: u8): vector<u64> {
        let j = 0;
        let found_cards = 0;
        let power = 1 << 12;
        let key = 0;
        let keys = vector::empty();
        while (j < 13) {
            let curr_bit = ranks & 1;
            if (curr_bit == 1) {
                found_cards = found_cards + 1;
                vector::push_back(&mut keys, power);
                key = key + power;
                if (found_cards == num) {
                    break
                };
            };
            ranks = ranks >> 1;
            j = j + 1;
            power = power >> 1;
        };
        assert!(found_cards == num, 0);
        keys
    }

    public fun parse_bits(ranks: u64): (u8, vector<u64>) {
        let j = 0;
        let found_cards = 0;
        let power = 1 << 12;
        let key = 0;
        let keys = vector::empty();
        while (j < 13) {
            let curr_bit = ranks & 1;
            if (curr_bit == 1) {
                found_cards = found_cards + 1;
                vector::push_back(&mut keys, power);
                key = key + power;
            };
            ranks = ranks >> 1;
            j = j + 1;
            power = power >> 1;
        };
        (found_cards, keys)
    }

    public fun get_hand(card_bits: u64, player_idx: u8): Hand {
        let counts = get_counts(card_bits);
        let quad_bits = vector::pop_back(&mut counts);
        let trips_bits = vector::pop_back(&mut counts);
        let pair_bits = vector::pop_back(&mut counts);
        let high_card_bits = vector::pop_back(&mut counts);
        let zero_bits = vector::pop_back(&mut counts);

        if (quad_bits > 0) {
            // four of a kind
            return Hand {
                key: vector<u64>[quad_bits],
                card_bits,
                hand_type: HAND_FOUR_OF_A_KIND,
                player_idx: player_idx,
            }
        } else {
            let flush = get_flush(card_bits);
            let straight = get_straight(8191 - zero_bits);
            if (straight > 0 && flush > 0) {
                let straight_flush = get_straight_flush(card_bits);
                if (straight_flush > 0) {
                    return Hand {
                        key: vector<u64>[(straight_flush as u64)],
                        card_bits,
                        hand_type: HAND_STRAIGHT_FLUSH,
                        player_idx: player_idx,

                    }
                };
            };
            let (num_trips, parsed_trips) = parse_bits(trips_bits);
            assert!(num_trips < 3, 0);
            if ((trips_bits > 0 && pair_bits > 0) || num_trips == 2) {
                if (num_trips == 2) {
                    return Hand {
                        key: parsed_trips,
                        card_bits,
                        hand_type: HAND_FULL_HOUSE,
                        player_idx: player_idx,

                    }
                };
                let parsed_pairs = parse_n_bits(pair_bits, 1);
                return Hand {
                    key: vector<u64>[(vector::pop_back(&mut parsed_trips) as u64), (vector::pop_back(&mut parsed_pairs) as u64)],
                    card_bits,
                    hand_type: HAND_FULL_HOUSE,
                    player_idx: player_idx,

                }
            } else if (flush > 0) {
                return Hand {
                    key: vector<u64>[flush],
                    card_bits,
                    hand_type: HAND_FLUSH,
                    player_idx: player_idx,

                }
            } else if (straight > 0) {
                return Hand {
                    key: vector<u64>[(straight as u64)],
                    card_bits,
                    hand_type: HAND_STRAIGHT,
                    player_idx: player_idx,

                }
            } else if (trips_bits > 0) {
                let keys = parse_n_bits(trips_bits, 1);
                let high_cards = parse_n_bits(high_card_bits, 2);
                vector::append(&mut keys, high_cards);
                return Hand {
                    key: keys,
                    card_bits,
                    hand_type: HAND_THREE_OF_A_KIND,
                    player_idx: player_idx,

                }
            } else if (pair_bits > 0) {
                let (num_pairs, parsed_pairs) = parse_bits(pair_bits);
                if (num_pairs > 1) {
                    while (vector::length(&parsed_pairs) > 2) {
                        vector::pop_back(&mut parsed_pairs);
                    };
                    let high_cards = parse_n_bits(high_card_bits, 1);
                    vector::append(&mut parsed_pairs, high_cards);
                    return Hand {
                        key: parsed_pairs,
                        card_bits,
                        hand_type: HAND_TWO_PAIR,
                        player_idx: player_idx,

                    }
                } else {
                    let high_cards = parse_n_bits(high_card_bits, 3);
                    vector::append(&mut parsed_pairs, high_cards);
                    return Hand {
                        key: parsed_pairs,
                        card_bits,
                        hand_type: HAND_PAIR,
                        player_idx: player_idx,

                    }
                }
            }
        };
        let high_cards = parse_n_bits(high_card_bits, 5);
        Hand {
            key: high_cards,
            card_bits,
            hand_type: HAND_HIGH_CARD,
            player_idx: player_idx,

        }
    }

    public fun cards_to_bits(cards: &vector<u8>): u64 {
        let i = 0;
        let num = vector::length(cards);
        let sum: u64 = 0u64;
        while (i < num) {
            let exp = *vector::borrow(cards, i);
            sum = sum + (1 << exp);
            i = i + 1;
        };
        sum
    }


    public fun compare_hands(hand1: &Hand, hand2: &Hand): u8 {
        if (hand1.hand_type > hand2.hand_type) {
            return HAND_BETTER
        } else if (hand1.hand_type < hand2.hand_type) {
            return HAND_WORSE
        } else {
            let l = vector::length(&hand1.key);
            assert!(l == vector::length(&hand2.key), 0);
            let i = 0;
            while (i < l) {
                let key_element1 = *vector::borrow(&hand1.key, i);
                let key_element2 = *vector::borrow(&hand2.key, i);
                if (key_element1 > key_element2) {
                    return HAND_BETTER
                } else if (key_element1 < key_element2) {
                    return HAND_WORSE
                };
                i = i + 1;
            };
        };
        HAND_EQUAL
    }

    public fun get_winning_hands(hands: &vector<Hand>, player_idxs: vector<u8>): (vector<u8>, vector<u64>) {
        let num_players = vector::length(&player_idxs);
        let first_idx = vector::pop_back(&mut player_idxs);
        let current_winning = vector::borrow(hands, (first_idx as u64));
        let winning_idxs = vector<u8>[current_winning.player_idx];
        let winning_bits = vector<u64>[current_winning.card_bits];

        let i = 1;
        while (i < num_players) {
            let current_idx = vector::pop_back(&mut player_idxs);
            let hand = vector::borrow(hands, (current_idx as u64));
            let player_idx = hand.player_idx;
            let comparison = compare_hands(hand, current_winning);
            if (comparison == HAND_BETTER) {
                // clear
                let k = 0;
                let len_hands = vector::length(&winning_idxs);
                while (k < len_hands) {
                    vector::pop_back(&mut winning_idxs);
                    vector::pop_back(&mut winning_bits);
                    k = k + 1;
                };

                // add
                current_winning = hand;
                vector::push_back(&mut winning_idxs, (player_idx as u8));
                vector::push_back(&mut winning_bits, hand.card_bits);
            } else if (comparison == HAND_EQUAL) {
                vector::push_back(&mut winning_idxs, (player_idx as u8));
                vector::push_back(&mut winning_bits, hand.card_bits);
            };
            i = i + 1;
        };
        (winning_idxs, winning_bits)
    }

    #[test]
    fun test_card() {
        // let cards: vector<u8> = vector<u8>[5,18,31,38,27,37,29];
        // let cards: vector<u8> = vector<u8>[5,18,31,8,21,47,51];

        // let cards: vector<u8> = vector<u8>[1,15,2,4,5,50,51];
        let cards: vector<u8> = vector<u8>[1,15,3,4,5,50,51];

        let bits = cards_to_bits(&cards);
        debug::print(&bits);
        let hand = get_hand(bits, 2);
        debug::print(&hand);

        let counts = get_counts(3023657046016);
        debug::print(&counts);
    }
}