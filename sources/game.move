module aliceandbobpoker::game {
    use sui::object::{Self, ID, UID, uid_to_address};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::vector;
    use std::debug;
    use sui::bcs;
    use sui::event;
    use sui::sui::SUI;
    // use sui::coin::{Self, Coin, mint_for_testing};
    use sui::coin::{Self, Coin};

    use sui::balance::{Self, Balance, zero};

    use aliceandbobpoker::crypto::{verify_public_key, zero_point, is_zero_point,
     copy_point_into, point_from_bytes, new_point, verify_decrypt,
     points_equal, three_points_from_bytes,
     peel_u256,
     verify_point_sum_equal,
     Point, CompressedCipherText,
     verify_zero_encrypt, verify_shuffle, verify_plain_hash,
     bytes_to_compressed_cipher_texts, point_is_c1_compressed, verify_reveal2,
     point_equals_compressed_point, new_compressed_point,
     compressed_point_is_c2_compressed, invert_point,
     uncompressed_bytes_to_compressed_cipher_texts, compressed_cipher_texts_equal,
     };


    use aliceandbobpoker::poker::{cards_to_bits, get_hand, get_winning_hands
    };

    const NUM_HIDDEN_CARDS: u8 = 2;

    const PUBLIC_CARD: u8 = 255;
    const NUM_ROUNDS: u8 = 4;

    const DECK_LENGTH: u8 = 52;
    const REVEAL_LENGTH: u64 = 5u64;

    const BET_CALL: u8 = 0u8;
    const BET_BET: u8 = 2u8;
    const BETLESS_CHECK: u8 = 3u8;
    const BETLESS_FOLD: u8 = 4u8;
    const BET_BLIND_BET: u8 = 5u8;

    const MAX_PLAYERS: u8 = 8;

    // struct StartGame has key, store {
    //     id: UID,
    //     game_id: ID
    // }

    struct JoinGame has key, store {
        id: UID,
        player: address,
        game_id: ID,
        point: Point,
        balance: u256,
        seat: u8,
    }

    struct LeaveGame has key, store {
        id: UID,
        player: address,
        game_id: ID,
    }

    struct Card has store, drop {
        cipher_text: CompressedCipherText,
        decrypts: vector<Point>,
        submitted_decrypt: vector<address>,
        completed_decrypt: bool,
        revealable: bool,
        revealed: bool,
        reveal_card: u8,
    }

    struct GameV2 has key {
        id: UID,
        hand_idx: u32,
        started: bool,
        shuffled: bool,
        admin: address,
        players: vector<address>,
        player_seats: vector<u8>,
        public_keys: vector<Point>,
        group_public_key: Point,
        deck: vector<Card>,
        rounds: vector<vector<u8>>,
        decrypt_round: u8,
        small_blind: u256,
        big_blind: u256,
        button_idx: u8,
        sb_submitted: bool,
        bb_submitted: bool,
        bet_round: u8,
        bet_player: u8,
        current_bet: u256,
        raise_amount: u256,
        current_bets: vector<u256>,
        current_has_bet: vector<u8>,
        current_hand_players: vector<u8>,
        player_balances: vector<u256>,
        cum_bets: vector<u256>,
        pot: Balance<SUI>,
        hand_over: bool,
        can_add_player: bool,
    }

    struct ShuffledDeck has key, store {
        id: UID,
        game_id: ID,
        hand_idx: u32,
        deck: vector<CompressedCipherText>,
        players: vector<address>,
        public_key: Point,
        hash: u256,
    }

    struct PartialDecryptV2 has key, store {
        id: UID,
        game_id: ID,
        hand_idx: u32,
        partials: vector<Point>,
        c1s: vector<Point>,
        public_key: Point,
        round: u8,
        from: address,
        final: bool,
    }

    struct PartialDecryptMany has key, store {
        id: UID,
        game_id: ID,
        hand_idx: u32,
        partials: vector<Point>,
        c1s: vector<Point>,
        public_key: Point,
        rounds: vector<u8>,
        from: address,
    }


    struct Bet has key, store {
        id: UID,
        coin: Coin<SUI>,
        game_id: ID,
        hand_idx: u32,
        player: address,
        amount: u256,
        round: u8,
        bet_type: u8,
    }

    struct Betless has key, store {
        id: UID,
        game_id: ID,
        hand_idx: u32,
        player: address,
        round: u8,
        betless_type: u8,
    }

    struct JoinEvent has copy, drop {
        player: address,
        game_id: ID,
    }

    struct LeaveEvent has copy, drop {
        player: address,
        game_id: ID,
    }

    struct AddPlayerEvent has copy, drop {
        player: address,
        game_id: ID,
    }

    struct RemovePlayerEvent has copy, drop {
        player: address,
        game_id: ID,
    }

    struct ShuffleEvent has copy, drop {
        game_id: ID,
        from: address,
        to: address,
    }

    struct BetEvent has copy, drop {
        game_id: ID,
        player: address,
        amount: u256,
        round: u8,
        bet_type: u8,
    }

    struct AddBetEvent has copy, drop {
        game_id: ID,
        hand_idx: u32,
        player: address,
        amount: u256,
        total_amount: u256,
        round: u8,
        bet_type: u8,
        is_raise: bool,
    }

    struct FoldEvent has copy, drop {
        game_id: ID,
        player: address,
        round: u8,
    }

    struct CheckEvent has copy, drop {
        game_id: ID,
        player: address,
        round: u8,
    }    

    struct AddFoldEvent has copy, drop {
        game_id: ID,
        hand_idx: u32,
        player: address,
        round: u8,
    }

    struct AddCheckEvent has copy, drop {
        game_id: ID,
        hand_idx: u32,
        player: address,
        round: u8,
    }

    // struct DecryptEvent has copy, drop {
    //     game_id: ID,
    //     player: address,
    //     round: u8,
    // }

    struct AddDecryptEvent has copy, drop {
        game_id: ID,
        hand_idx: u32,
        player: address,
        round: u8,
        complete: bool,
    }

    struct RevealEvent has copy, drop {
        game_id: ID,
        hand_idx: u32,
        // player: address,
        card_idx: u8,
        round: u8,
        player: address,
        revealed_card: u8,
    }

    struct PayoutEvent has copy, drop {
        player: address,
        game_id: ID,
        hand_idx: u32,
        amount: u256,
        hand_bits: u64,
    }

    struct NewHandEvent has copy, drop {
        game_id: ID,
        hand_idx: u32,
    }


    struct ResetEvent has copy, drop {
        game_id: ID,
        hand_idx: u32,
    }



    fun init(_ctx: &mut TxContext) {
    }

    public fun new_join_game(game_id: ID, public_key_bytes: vector<u8>, proof_bytes: vector<u8>, balance: u256, seat: u8, ctx: &mut TxContext): JoinGame {
        let verified = verify_public_key(public_key_bytes, proof_bytes);
        let point = point_from_bytes(public_key_bytes);
        let is_zero = is_zero_point(&point);
        assert!(verified, 0);
        assert!(!is_zero, 0);
        JoinGame {
            id: object::new(ctx),
            player: tx_context::sender(ctx),
            game_id,
            point,
            balance,
            seat,
        }
    }

    public fun new_leave_game(game_id: ID, ctx: &mut TxContext): LeaveGame {
        LeaveGame {
            id: object::new(ctx),
            player: tx_context::sender(ctx),
            game_id,
        }
    }

    public fun new_game2(admin: address, group_public_key: Point, small_blind: u256, big_blind: u256, ctx: &mut TxContext): GameV2 {
        let id = object::new(ctx);
        assert!(small_blind <= big_blind, 0);
        assert!(small_blind > 0, 0);
        assert!(big_blind > 0, 0);
        let game = GameV2{
            id,
            hand_idx: 0,
            started: false,
            shuffled: false,
            admin: admin,
            players: vector::empty(),
            player_seats: vector::empty(),
            public_keys: vector::empty(),
            group_public_key,
            deck: vector::empty(),
            rounds: vector::empty(),
            decrypt_round: 0,
            small_blind,
            big_blind,
            button_idx: 0,
            sb_submitted: false,
            bb_submitted: false,
            bet_round: 0,
            bet_player: 0,
            current_bet: 0,
            raise_amount: 0,
            current_bets: vector::empty(),
            current_has_bet: vector::empty(),
            current_hand_players: vector::empty(),
            player_balances: vector::empty(),
            cum_bets: vector::empty(),
            pot: zero(),
            hand_over: false,
            can_add_player: true,
        };
        game
    }

    public entry fun create_game2(at: address, small_blind: u256, big_blind: u256, ctx: &mut TxContext): address {
        let group_public_key = zero_point();
        let game = new_game2(at, group_public_key, small_blind, big_blind, ctx);
        let addr = uid_to_address(&game.id);
        transfer::transfer(game, at);
        addr
    }

    public entry fun join(at: address, game_id: ID, public_key_bytes: vector<u8>, proof_bytes: vector<u8>, balance: u256, seat: u8, ctx: &mut TxContext) {
        let public_key = new_join_game(game_id, public_key_bytes, proof_bytes, balance, seat, ctx);
        transfer::transfer(public_key, at);
        event::emit(JoinEvent {
            player: tx_context::sender(ctx),
            game_id: game_id
        });
    }

    public entry fun leave(at: address, game_id: ID, ctx: &mut TxContext) {
        let leave_game = new_leave_game(game_id, ctx);
        transfer::transfer(leave_game, at);
        event::emit(LeaveEvent {
            player: tx_context::sender(ctx),
            game_id: game_id
        });
    }

    public entry fun add_player2(game: &mut GameV2, public_key: JoinGame, input_bytes: vector<u8>, proof_bytes: vector<u8>, _ctx: &mut TxContext) {
        assert!(game.can_add_player, 0);
        let JoinGame{id, player, game_id, point, balance, seat} = public_key;
        assert!(&game_id == &object::uid_to_inner(&game.id), 0);
        let (found, _) = vector::index_of(&game.players, &player);
        assert!(!found, 0);
        let seat_exists = vector::contains(&game.player_seats, &seat);
        assert!(!seat_exists, 0);
        assert!(balance >= game.big_blind, 0);

        assert!(seat < MAX_PLAYERS, 0);
        let seats_len = vector::length(&game.player_seats);
        let i = 0;
        let seat_inserted = false;
        while (i < seats_len) {
            let existing_seat = *vector::borrow(&game.player_seats, i);
            if (seat < existing_seat) {
                vector::insert(&mut game.player_seats, seat, i);
                vector::insert(&mut game.players, player, i);
                vector::insert(&mut game.public_keys, point, i);
                vector::insert(&mut game.player_balances, balance, i);
                seat_inserted = true;
                break
            };
            i = i + 1;
        };
        if (!seat_inserted) {
            vector::push_back(&mut game.player_seats, seat);
            vector::push_back(&mut game.players, player);
            vector::push_back(&mut game.public_keys, point);
            vector::push_back(&mut game.player_balances, balance);
        };
        let points = vector::empty();
        vector::push_back(&mut points, game.group_public_key);
        vector::push_back(&mut points, point);

        let new_public_key = verify_point_sum_equal(points, input_bytes, proof_bytes);
        copy_point_into(&new_public_key, &mut game.group_public_key);

        event::emit(AddPlayerEvent {
            player: player,
            game_id: object::uid_to_inner(&game.id),
        });

        if (vector::length(&game.players) > 1) {
            game.started = true;
            // event::emit(NewHandEvent {
            //     game_id: object::uid_to_inner(&game.id),
            //     hand_idx: game.hand_idx,
            // });
        };

        object::delete(id);

    }

    public entry fun remove_player(game: &mut GameV2, leave_game: LeaveGame, input_bytes: vector<u8>, proof_bytes: vector<u8>, _ctx: &mut TxContext) {
        let LeaveGame{id, player, game_id} = leave_game;
        assert!(&game_id == &object::uid_to_inner(&game.id), 0);
        inner_remove_player(game, player, input_bytes, proof_bytes);
        object::delete(id);
    }


    public entry fun remove_bust_player(game: &mut GameV2, player: address, input_bytes: vector<u8>, proof_bytes: vector<u8>, _ctx: &mut TxContext) {
        let (found, idx) = vector::index_of(&game.players, &player);
        assert!(found, 0);
        let player_balance = *vector::borrow(&game.player_balances, idx);
        assert!(player_balance < game.big_blind, 0);

        inner_remove_player(game, player, input_bytes, proof_bytes);
    }


    public fun inner_remove_player(game: &mut GameV2, player: address, input_bytes: vector<u8>, proof_bytes: vector<u8>) {
        assert!(game.can_add_player, 0);
        let (found, idx) = vector::index_of(&game.players, &player);
        assert!(found, 0);

        vector::remove(&mut game.players, idx);
        let point = vector::remove(&mut game.public_keys, idx);
        vector::remove(&mut game.player_balances, idx);
        vector::remove(&mut game.player_seats, idx);

        let neg_point = invert_point(&point);
        let points = vector::empty();
        vector::push_back(&mut points, game.group_public_key);
        vector::push_back(&mut points, neg_point);

        let new_public_key = verify_point_sum_equal(points, input_bytes, proof_bytes);
        copy_point_into(&new_public_key, &mut game.group_public_key);

        // shift button
        let new_button_idx =  if ((idx as u8) < game.button_idx) {
            game.button_idx - 1
        } else {
            game.button_idx
        };
        let new_len = (vector::length(&game.players) as u8);
        if (new_len > 0) {
            game.button_idx = new_button_idx % new_len
        } else {
            game.button_idx = 0;
        };

        if (vector::length(&game.players) < 2) {
            game.started = false;
        };

        event::emit(RemovePlayerEvent {
            player: player,
            game_id: object::uid_to_inner(&game.id),
        });
    }

    public entry fun shuffle_plain(at: address, game_id: ID, hand_idx: u32, ser_output: vector<u8>, zero_input_bytes: vector<u8>, zero_proof_bytes: vector<u8>,
        shuffle_input_bytes: vector<u8>, shuffle_proof_bytes: vector<u8>, ctx: &mut TxContext) {
        let zero_verified = verify_zero_encrypt(zero_input_bytes, zero_proof_bytes);
        assert!(zero_verified, 0);
        let shuffle_verified = verify_shuffle(shuffle_input_bytes, shuffle_proof_bytes);
        assert!(shuffle_verified, 0);

        let shuffle_input_bcs = bcs::new(shuffle_input_bytes);
        let input_hash = peel_u256(&mut shuffle_input_bcs);
        let zeros_hash = peel_u256(&mut shuffle_input_bcs);
        let output_hash = peel_u256(&mut shuffle_input_bcs);
        
        let zero_input_bcs = bcs::new(zero_input_bytes);
        let zeros_hash_proven = peel_u256(&mut zero_input_bcs);
        let pub_key_x = peel_u256(&mut zero_input_bcs);
        let pub_key_y = peel_u256(&mut zero_input_bcs);

        assert!(zeros_hash == zeros_hash_proven, 0);
        verify_plain_hash(input_hash);

        let players = vector::empty();
        vector::push_back(&mut players, tx_context::sender(ctx));
        let deck = bytes_to_compressed_cipher_texts(ser_output, (DECK_LENGTH as u64));
        let shuffled_deck = ShuffledDeck {
            id: object::new(ctx),
            game_id,
            hand_idx,
            deck,
            players,
            hash: output_hash,
            public_key: new_point(pub_key_x, pub_key_y)
        };
        transfer::transfer(shuffled_deck, at);
        event::emit(ShuffleEvent {
            game_id: game_id,
            from: tx_context::sender(ctx),
            to: at,
        });
    }

    public entry fun shuffle(at: address, shuffled_deck: ShuffledDeck, ser_output: vector<u8>, zero_input_bytes: vector<u8>, zero_proof_bytes: vector<u8>,
        shuffle_input_bytes: vector<u8>, shuffle_proof_bytes: vector<u8>, ctx: &mut TxContext) {
        let zero_verified = verify_zero_encrypt(zero_input_bytes, zero_proof_bytes);
        assert!(zero_verified, 0);
        let shuffle_verified = verify_shuffle(shuffle_input_bytes, shuffle_proof_bytes);
        assert!(shuffle_verified, 0);
        let ShuffledDeck{id, game_id, hand_idx,
        deck: _deck, players, hash, public_key} = shuffled_deck;

        let shuffle_input_bcs = bcs::new(shuffle_input_bytes);
        let input_hash = peel_u256(&mut shuffle_input_bcs);
        let zeros_hash = peel_u256(&mut shuffle_input_bcs);
        let output_hash = peel_u256(&mut shuffle_input_bcs);
        
        let zero_input_bcs = bcs::new(zero_input_bytes);
        let zeros_hash_proven = peel_u256(&mut zero_input_bcs);
        let pub_key_x = peel_u256(&mut zero_input_bcs);
        let pub_key_y = peel_u256(&mut zero_input_bcs);

        let new_public_key = new_point(pub_key_x, pub_key_y);
        assert!(points_equal(&new_public_key, &public_key), 0);

        assert!(zeros_hash == zeros_hash_proven, 0);
        assert!(hash == input_hash, 0);

        vector::push_back(&mut players, tx_context::sender(ctx));
        let new_deck = bytes_to_compressed_cipher_texts(ser_output, (DECK_LENGTH as u64));  
        let new_shuffled_deck = ShuffledDeck {
            id: object::new(ctx),
            game_id,
            hand_idx,
            deck: new_deck,
            players,
            hash: output_hash,
            public_key: new_public_key
        };
        transfer::transfer(new_shuffled_deck, at);
        object::delete(id);
        event::emit(ShuffleEvent {
            game_id: game_id,
            from: tx_context::sender(ctx),
            to: at,
        });
    }

    public fun add_cards_to_game(game: &mut GameV2, deck: vector<CompressedCipherText>) {
        let i = 0;
        let deck_length = vector::length(&deck);
        vector::reverse(&mut deck);
        assert!(vector::length(&game.deck) == 0, 0);
        while (i < deck_length) {
            let cipher_text = vector::pop_back(&mut deck);
            let card = Card {
                cipher_text,
                decrypts: vector::empty(),
                submitted_decrypt: vector::empty(),
                completed_decrypt: false,
                revealable: false,
                revealed: false,
                reveal_card: 0,
            };
            vector::push_back(&mut game.deck, card);
            i = i + 1;
        };
    }

    public entry fun complete_shuffle2(game: &mut GameV2, shuffled_deck: ShuffledDeck, ser_uncompressed: vector<u8>, _ctx: &mut TxContext) {
        assert!(game.started, 0);
        let ShuffledDeck{id, game_id, hand_idx,
        deck, players, hash, public_key} = shuffled_deck;

        let (verified_deck, deck_hash) = uncompressed_bytes_to_compressed_cipher_texts(ser_uncompressed, (DECK_LENGTH as u64));
        assert!(deck_hash == hash, 0);
        assert!(vector::length(&deck) == vector::length(&verified_deck), 0);
        let j = 0;
        let deck_length = vector::length(&deck);
        while (j < deck_length) {
            let card = vector::borrow(&deck, j);
            let verified_card = vector::borrow(&verified_deck, j);
            assert!(compressed_cipher_texts_equal(card, verified_card), 0);
            j = j + 1;
        };

        assert!(hand_idx == game.hand_idx, 0);
        assert!(game_id == object::uid_to_inner(&game.id), 0);
        assert!(points_equal(&game.group_public_key, &public_key), 0);
        let i = 0;
        let num_players = vector::length(&game.players);
        while (i < num_players) {
            let player = vector::borrow(&game.players, i);
            let shuffled_player = vector::borrow(&players, i);
            assert!(player == shuffled_player, 0);
            vector::push_back(&mut game.current_hand_players, (i as u8));
            i = i + 1;
        };
        add_cards_to_game(game, deck);
        game.shuffled = true;
        game.can_add_player = false;
        object::delete(id);

        // compute card rounds
        let round_0 = vector::empty();
        i = 0;
        while (i < vector::length(&game.players) * (NUM_HIDDEN_CARDS as u64)) {
            let player_idx = i % num_players;
            vector::push_back(&mut round_0, (player_idx as u8));
            i = i + 1;
        };
        vector::push_back(&mut game.rounds, round_0);
        // flop
        vector::push_back(&mut game.rounds, vector<u8>[PUBLIC_CARD, PUBLIC_CARD, PUBLIC_CARD]);
        // turn
        vector::push_back(&mut game.rounds, vector<u8>[PUBLIC_CARD]);
        // river
        vector::push_back(&mut game.rounds, vector<u8>[PUBLIC_CARD]);
        new_betting_round(game, 0);

        // special case for heads-up
        if (num_players == 2) {
            game.bet_player = ((0 + game.button_idx) % (num_players as u8));
        } else {
            game.bet_player = ((1 + game.button_idx) % (num_players as u8));
        };

        game.hand_idx = game.hand_idx + 1;
        event::emit(NewHandEvent {
            game_id: object::uid_to_inner(&game.id),
            hand_idx: game.hand_idx,
        });
    }


    public entry fun decrypt_many(at: address, game_id: ID, hand_idx: u32, rounds: vector<u8>, all_input_bytes: vector<u8>, all_proof_bytes: vector<u8>, ctx: &mut TxContext) {
        let bcs_inputs = bcs::new(all_input_bytes);
        let peeled_inputs = bcs::peel_vec_vec_u8(&mut bcs_inputs);
        let bcs_proof = bcs::new(all_proof_bytes);
        let peeled_proofs = bcs::peel_vec_vec_u8(&mut bcs_proof);
        let i = 0;
        let all_decrypted = vector::empty();
        let all_c1 = vector::empty();
        let last_public_key = zero_point();
        assert!(vector::length(&peeled_proofs) == vector::length(&peeled_proofs), 0);
        let input_length = vector::length(&peeled_inputs);

        while (i < input_length) {
            let input_bytes = vector::pop_back(&mut peeled_inputs);
            let proof_bytes = vector::pop_back(&mut peeled_proofs);
            let verified = verify_decrypt(input_bytes, proof_bytes);
            assert!(verified, 0);
            let (public_key, decrypted, c1) = three_points_from_bytes(input_bytes);
            if (i > 0) {
                let equal = (&last_public_key == &public_key);
                assert!(equal, 0);
            };
            last_public_key = public_key;
            vector::push_back(&mut all_decrypted, decrypted);
            vector::push_back(&mut all_c1, c1);
            i = i + 1;
        };
        let partial = PartialDecryptMany {
            id: object::new(ctx),
            game_id,
            hand_idx,
            partials: all_decrypted,
            c1s: all_c1,
            public_key: last_public_key,
            rounds,
            from: tx_context::sender(ctx),
        };
        transfer::transfer(partial, at);
    }

    public entry fun add_many_decrypt_many(game: &mut GameV2, partial_decrypt_many_vector: vector<PartialDecryptMany>, _ctx: &mut TxContext) {
        let i = 0;
        let num_partials = vector::length(&partial_decrypt_many_vector);
        while (i < num_partials) {
            let partial_decrypt_many = vector::pop_back(&mut partial_decrypt_many_vector);
            add_decrypt_many(game, partial_decrypt_many, _ctx);
            i = i + 1;
        };
        vector::destroy_empty(partial_decrypt_many_vector);
    }

    public entry fun add_decrypt_many(game: &mut GameV2, partial_decrypt_many: PartialDecryptMany, _ctx: &mut TxContext) {
        assert!(game.sb_submitted && game.bb_submitted, 0);
        let PartialDecryptMany{id, game_id, hand_idx, partials, c1s, public_key, rounds, from} = partial_decrypt_many;
        assert!(game_id == object::uid_to_inner(&game.id), 0);
        assert!(game.shuffled, 0);
        assert!(hand_idx == game.hand_idx, 0);
        let (game_contains_player, player_idx) = vector::index_of(&game.players, &from);
        assert!(game_contains_player, 0);
        let player_public_key = vector::borrow(&game.public_keys, player_idx);
        let public_key_equal = (player_public_key == &public_key);
        assert!(public_key_equal, 0);

        vector::reverse(&mut partials);
        vector::reverse(&mut c1s);

        let l = 0;
        let num_rounds = vector::length(&rounds);
        while (l < num_rounds) {
            let round_idx = *(vector::borrow(&rounds, l));
            assert!(round_idx < NUM_ROUNDS, 0);
            let final = 
            if (round_idx == 0) {
                // hole cards
                assert!((game.bet_round == NUM_ROUNDS), 0);
                true
            } else {
                assert!(round_idx >= game.decrypt_round, 0);
                false
            };

            let round_decrypted = true;
            let num_players = vector::length(&game.players);
            let j = 0;
            let k = 0;
            while (j < NUM_ROUNDS) {
                let round = vector::borrow(&game.rounds, (j as u64));
                let i = 0;
                while (i < vector::length(round)) {
                    if (round_idx == j) {
                        let player_idx = *(vector::borrow(round, i));
                        let player = {
                            if (player_idx == PUBLIC_CARD) {
                                &@0x0
                            } else {
                                vector::borrow(&game.players, (player_idx as u64))
                            }
                        };
                        if ((player == &from && final) || (player != &from && !final))
                        {
                            let partial = vector::pop_back(&mut partials);
                            let c1 = vector::pop_back(&mut c1s);

                            let card = vector::borrow_mut(&mut game.deck, k);
                            let already_submitted = vector::contains(&card.submitted_decrypt, &from);
                            assert!(!already_submitted, 0);
                            assert!(point_is_c1_compressed(&c1, &card.cipher_text), 0);
                            vector::push_back(&mut card.decrypts, partial);
                            vector::push_back(&mut card.submitted_decrypt, from);

                            if ((player_idx != PUBLIC_CARD && vector::length(&card.decrypts) == (num_players as u64) - 1)
                            || (player_idx == PUBLIC_CARD && vector::length(&card.decrypts) == (num_players as u64))) {
                                card.completed_decrypt = true;
                            };
                            if (vector::length(&card.decrypts) == (num_players as u64)) {
                                card.revealable = true;
                            };
                        };
                        {
                            let card = vector::borrow(&game.deck, k);
                            if ((player_idx != PUBLIC_CARD && vector::length(&card.decrypts) < (num_players as u64) - 1)
                            || (player_idx == PUBLIC_CARD && vector::length(&card.decrypts) < (num_players as u64))) {
                                round_decrypted = false;
                            };
                        };

                    };
                    i = i + 1;
                    k = k + 1;
                };
                j = j + 1;
            };
            if (round_decrypted && !final) {
                game.decrypt_round = game.decrypt_round + 1;
            };
            event::emit(AddDecryptEvent {
                game_id,
                hand_idx,
                player: from,
                round: (round_idx as u8),
                complete: round_decrypted,
            });
            l = l + 1;
        };

        object::delete(id);
        // event::emit(AddDecryptEvent {
        //     game_id: game_id,
        //     player: from,
        //     round: (round_idx as u8),
        // });
    }

    public entry fun decrypt2(at: address, game_id: ID, hand_idx: u32, idx: u64, final: bool, all_input_bytes: vector<u8>, all_proof_bytes: vector<u8>, ctx: &mut TxContext) {
        let bcs_inputs = bcs::new(all_input_bytes);
        let peeled_inputs = bcs::peel_vec_vec_u8(&mut bcs_inputs);
        let bcs_proof = bcs::new(all_proof_bytes);
        let peeled_proofs = bcs::peel_vec_vec_u8(&mut bcs_proof);
        let i = 0;
        let all_decrypted = vector::empty();
        let all_c1 = vector::empty();
        let last_public_key = zero_point();
        assert!(vector::length(&peeled_proofs) == vector::length(&peeled_proofs), 0);
        let input_length = vector::length(&peeled_inputs);

        while (i < input_length) {
            let input_bytes = vector::pop_back(&mut peeled_inputs);
            let proof_bytes = vector::pop_back(&mut peeled_proofs);
            let verified = verify_decrypt(input_bytes, proof_bytes);
            assert!(verified, 0);
            let (public_key, decrypted, c1) = three_points_from_bytes(input_bytes);
            if (i > 0) {
                let equal = (&last_public_key == &public_key);
                assert!(equal, 0);
            };
            last_public_key = public_key;
            vector::push_back(&mut all_decrypted, decrypted);
            vector::push_back(&mut all_c1, c1);
            i = i + 1;
        };
        let partial = PartialDecryptV2 {
            id: object::new(ctx),
            game_id,
            hand_idx,
            partials: all_decrypted,
            c1s: all_c1,
            public_key: last_public_key,
            round: (idx as u8),
            from: tx_context::sender(ctx),
            final,
        };
        transfer::transfer(partial, at);
        // event::emit(DecryptEvent {
        //     game_id: game_id,
        //     player: tx_context::sender(ctx),
        //     round: (idx as u8),
        // });
    }

    public entry fun add_many_decrypt2(game: &mut GameV2, partial_decrypt_vector: vector<PartialDecryptV2>, _ctx: &mut TxContext) {
        let i = 0;
        let num_partials = vector::length(&partial_decrypt_vector);
        while (i < num_partials) {
            let partial_decrypt = vector::pop_back(&mut partial_decrypt_vector);
            add_decrypt2(game, partial_decrypt, _ctx);
            i = i + 1;
        };
        vector::destroy_empty(partial_decrypt_vector);
    }


    public entry fun add_decrypt2(game: &mut GameV2, partial_decrypt: PartialDecryptV2, _ctx: &mut TxContext) {
        assert!(game.sb_submitted && game.bb_submitted, 0);
        let PartialDecryptV2{id, game_id, hand_idx, partials, c1s, public_key, round: round_idx, from, final} = partial_decrypt;
        assert!(game_id == object::uid_to_inner(&game.id), 0);
        assert!(game.shuffled, 0);
        assert!(hand_idx == game.hand_idx, 0);
        let (game_contains_player, player_idx) = vector::index_of(&game.players, &from);
        assert!(game_contains_player, 0);
        let player_public_key = vector::borrow(&game.public_keys, player_idx);
        let public_key_equal = (player_public_key == &public_key);
        assert!(public_key_equal, 0);
        assert!(round_idx < NUM_ROUNDS, 0);
        if (final) {
            assert!(game.decrypt_round == NUM_ROUNDS, 0);
            assert!(game.bet_round == NUM_ROUNDS, 0);
            // hole cards
            assert!(round_idx == 0, 0);
        } else {
            assert!(game.decrypt_round == round_idx, 0);
            assert!(((game.decrypt_round == game.bet_round) ||
            (game.bet_round == NUM_ROUNDS)), 0);
        };

        vector::reverse(&mut partials);
        vector::reverse(&mut c1s);
        let round_decrypted = true;
        let num_players = vector::length(&game.players);
        let j = 0;
        let k = 0;
        while (j < NUM_ROUNDS) {
            let round = vector::borrow(&game.rounds, (j as u64));
            let i = 0;
            while (i < vector::length(round)) {
                if (round_idx == j) {
                    let player_idx = *(vector::borrow(round, i));
                    let player = {
                        if (player_idx == PUBLIC_CARD) {
                            &@0x0
                            // &tx_context::sender(ctx)
                        } else {
                            vector::borrow(&game.players, (player_idx as u64))
                        }
                    };
                    // assert!((player == &from && final) || (player != &from && !final), 0);
                    if ((player == &from && final) || (player != &from && !final))
                    {
                        let partial = vector::pop_back(&mut partials);
                        let c1 = vector::pop_back(&mut c1s);

                        let card = vector::borrow_mut(&mut game.deck, k);
                        let already_submitted = vector::contains(&card.submitted_decrypt, &from);
                        assert!(!already_submitted, 0);
                        assert!(point_is_c1_compressed(&c1, &card.cipher_text), 0);
                        vector::push_back(&mut card.decrypts, partial);
                        vector::push_back(&mut card.submitted_decrypt, from);

                        if ((player_idx != PUBLIC_CARD && vector::length(&card.decrypts) == (num_players as u64) - 1)
                        || (player_idx == PUBLIC_CARD && vector::length(&card.decrypts) == (num_players as u64))) {
                            card.completed_decrypt = true;
                        };
                        if (vector::length(&card.decrypts) == (num_players as u64)) {
                            card.revealable = true;
                        };
                    };
                    {
                        let card = vector::borrow(&game.deck, k);
                        if ((player_idx != PUBLIC_CARD && vector::length(&card.decrypts) < (num_players as u64) - 1)
                        || (player_idx == PUBLIC_CARD && vector::length(&card.decrypts) < (num_players as u64))) {
                            round_decrypted = false;
                        };
                    };
                };
                i = i + 1;
                k = k + 1;
            };
            j = j + 1;
        };
        if (round_decrypted && !final) {
            game.decrypt_round = game.decrypt_round + 1;
        };
        object::delete(id);
        event::emit(AddDecryptEvent {
            game_id,
            hand_idx,
            player: from,
            round: (round_idx as u8),
            complete: round_decrypted
        });
    }


    public entry fun reveal_many(game: &mut GameV2, card_indices: vector<u8>, all_input_bytes: vector<u8>, all_proof_bytes: vector<u8>, ctx: &mut TxContext) {
        let bcs_inputs = bcs::new(all_input_bytes);
        let peeled_inputs = bcs::peel_vec_vec_u8(&mut bcs_inputs);
        let bcs_proof = bcs::new(all_proof_bytes);
        let peeled_proofs = bcs::peel_vec_vec_u8(&mut bcs_proof);

        assert!(vector::length(&peeled_proofs) == vector::length(&peeled_inputs), 0);
        assert!(vector::length(&card_indices) == vector::length(&peeled_inputs), 0);
        let input_length = vector::length(&peeled_inputs);
        let i = 0;
        while (i < input_length) {
            let input_bytes = vector::pop_back(&mut peeled_inputs);
            let proof_bytes = vector::pop_back(&mut peeled_proofs);
            let card_idx = vector::pop_back(&mut card_indices);
            reveal2(game, card_idx, input_bytes, proof_bytes, ctx);
            i = i + 1;
        };

        // find winners too if end of game
        if (game.decrypt_round == NUM_ROUNDS && game.bet_round == NUM_ROUNDS && vector::length(&game.current_hand_players) > 1) {
            find_winners(game, ctx);
        }
    }



    public entry fun reveal2(game: &mut GameV2, card_idx: u8, input_bytes: vector<u8>, proof_bytes: vector<u8>, _ctx: &mut TxContext) {
        let verified = verify_reveal2(input_bytes, proof_bytes);
        assert!(verified, 0);
        let bsc = bcs::new(input_bytes);
        let flags = peel_u256(&mut bsc);
        let _outx = peel_u256(&mut bsc);
        let c2x = peel_u256(&mut bsc);

        let card = vector::borrow_mut(&mut game.deck, (card_idx as u64));
        assert!(card.revealable, 0);
        assert!(!card.revealed, 0);
        let i = 0;
        let num_decrypts = vector::length(&card.decrypts);
        while (i < REVEAL_LENGTH) {
            let decrypt_x = peel_u256(&mut bsc);
            if (i < num_decrypts) {
                let flag = ((flags & 1) as u8) == 1;
                let compressed_c1 = new_compressed_point(decrypt_x, flag);
                let decrypt = vector::borrow(&card.decrypts, i);
                assert!(point_equals_compressed_point(decrypt, &compressed_c1), 0);
            } else {
                assert!(decrypt_x == 0, 0);
                assert!(((flags & 1) as u8) == 0, 0);
            };
            i = i + 1;
            flags = flags >> 1;
        };
        let c2_flag = ((flags & 1) as u8) == 1;
        flags = flags >> 1;
        let c2_compressed = new_compressed_point(c2x, c2_flag);
        assert!(compressed_point_is_c2_compressed(&c2_compressed, &card.cipher_text), 0);

        let _out_flag = ((flags & 1) as u8) == 1;
        flags = flags >> 1;
        card.revealed = true;
        assert!(card.revealable, 0);
        let revealed_card = (flags as u8);

        assert!(revealed_card > 0 && revealed_card <= DECK_LENGTH, 0);
        // subtract 1 because revealed card is between 1 and 52 inclusive (is the solution to X * G = C2)
        // but the deck is indexed from 0 to 51
        card.reveal_card = revealed_card - 1;


        let num_players = (vector::length(&game.players) as u8);
        let num_hidden_cards = (num_players * NUM_HIDDEN_CARDS as u8);
        let round = if (card_idx < num_hidden_cards) {
            0
        } else if (card_idx < (num_hidden_cards + 3)) {
            1
        } else if (card_idx < (num_hidden_cards + 4)) {
            2
        } else {
            3
        };
        let player = if (round == 0) {
            let player_idx = card_idx % num_players;
            *vector::borrow(&game.players, (player_idx as u64))
        } else {
            @0x0
        };

        event::emit(RevealEvent {
            game_id: object::uid_to_inner(&game.id),
            hand_idx: game.hand_idx,
            card_idx,
            round,
            player,
            revealed_card: card.reveal_card,
        });
    }

    public fun get_pots(game: &GameV2): (vector<u256>, vector<u256>, vector<vector<u8>>) {
        let num_players = vector::length(&game.players);
        let num_showdown_players = vector::length(&game.current_hand_players);
        let pot_bet_amounts = vector::empty();
        let pot_amounts = vector::empty();
        let pot_players = vector::empty();
        let last_pot_bet_size = 0;
        while (true) {
            let j = 0;
            let min_so_far = (balance::value(&game.pot) as u256);
            let players_in_pot = vector::empty();
            let found_new_pot = false;
            while (j < num_showdown_players) {
                let player_idx = *(vector::borrow(&game.current_hand_players, j));
                let player_cum_bet = *vector::borrow(&game.cum_bets, (player_idx as u64));
                if (player_cum_bet > last_pot_bet_size) {
                    vector::push_back(&mut players_in_pot, (j as u8));
                    found_new_pot = true;
                    if (player_cum_bet < min_so_far) {
                        min_so_far = player_cum_bet;
                    };
                };
                j = j + 1;
            };
            if (found_new_pot) {
                vector::push_back(&mut pot_players, players_in_pot);
                let current_pot_bet_size = (min_so_far - last_pot_bet_size);
                let k = 0;
                let pot_value = 0;
                while (k < num_players) {
                    let player_cum_bet = *vector::borrow(&game.cum_bets, k);
                    if (player_cum_bet > last_pot_bet_size) {
                        let pot_contribution = if (player_cum_bet < min_so_far) {
                            player_cum_bet - last_pot_bet_size
                        } else {
                            current_pot_bet_size
                        };
                        pot_value = pot_value + pot_contribution;
                    };
                    k = k + 1;
                };
                vector::push_back(&mut pot_amounts, pot_value);
                vector::push_back(&mut pot_bet_amounts, min_so_far);
                last_pot_bet_size = min_so_far;
            } else {
                break
            };
        };
        (pot_amounts, pot_bet_amounts, pot_players)
    }

    public entry fun find_winners(game: &mut GameV2, ctx: &mut TxContext) {
        assert!(game.decrypt_round == NUM_ROUNDS, 0);
        assert!(game.bet_round == NUM_ROUNDS, 0);
        let num_players = vector::length(&game.players);
        let num_showdown_players = vector::length(&game.current_hand_players);
        assert!(num_showdown_players > 1, 0);
        assert!(!game.hand_over, 0);
        game.hand_over = true;

        // get pots
        let (pot_amounts, pot_bet_amounts, pot_players) = get_pots(game);

        //get hands
        let player_cards = vector::empty();
        let i = 0;
        while (i < num_showdown_players) {
            vector::push_back(&mut player_cards, vector::empty());
            i = i + 1;
        };
        let j = 0;
        let k = 0;
        while (j < NUM_ROUNDS) {
            let round = vector::borrow(&game.rounds, (j as u64));
            let i = 0;
            while (i < vector::length(round)) {
                let card = vector::borrow(&game.deck, k);
                let player_idx = *(vector::borrow(round, i));
                if (player_idx == PUBLIC_CARD) {
                    let l = 0;
                    // while (l < vector::length(&game.players)) {
                    while (l < num_showdown_players) {
                        let hand = vector::borrow_mut(&mut player_cards, l);
                        assert!(card.revealed, 0);
                        vector::push_back(hand, (card.reveal_card as u8));
                        l = l + 1;
                    };
                } else {
                    let (found, idx) = vector::index_of(&game.current_hand_players, &player_idx);
                    if (found) {
                        let hand = vector::borrow_mut(&mut player_cards, (idx as u64));
                        assert!(card.revealed, 0);
                        vector::push_back(hand, (card.reveal_card as u8));
                    };
                };
                i = i + 1;
                k = k + 1;
            };
            j = j + 1;
        };

        // compute hands
        let i = 0;
        let hands = vector::empty();
        while (i < num_showdown_players) {
            let player_idx = *(vector::borrow(&game.current_hand_players, i));
            let cards = vector::borrow(&player_cards, i);
            let cards_bits = cards_to_bits(cards);
            let hand = get_hand(cards_bits, player_idx);
            debug::print(&hand);
            vector::push_back(&mut hands, hand);
            i = i + 1;
        };

        // compute winners
        let i = 0;
        let num_pots = vector::length(&pot_players);
        while (i < num_pots) {
            let players_in_pot = vector::pop_back(&mut pot_players);
            let pot_amount = vector::pop_back(&mut pot_amounts);
            let pot_bet_amount = vector::pop_back(&mut pot_bet_amounts);
            let (winners, winning_bits) = get_winning_hands(&hands, players_in_pot);
            let num_winners = vector::length(&winners);
            let pot_portion = pot_amount / (num_winners as u256);
            let j = 0;
            debug::print(&winners);
            debug::print(&pot_amount);

            debug::print(&num_winners);
            while (j < num_winners) {
                let player_idx = vector::pop_back(&mut winners);
                let hand_bits = vector::pop_back(&mut winning_bits);
                let player = *vector::borrow(&game.players, (player_idx as u64));

                let player_balance = vector::borrow_mut(&mut game.player_balances, (player_idx as u64));
                let new_player_balance = *player_balance + pot_portion;
                vector::push_back(&mut game.player_balances, new_player_balance);
                vector::swap_remove(&mut game.player_balances, (player_idx as u64));

                let coin = coin::take(&mut game.pot, (pot_portion as u64), ctx);
                transfer::public_transfer(coin, player);
                debug::print(&pot_portion);
                debug::print(&player);
                let payout_event = PayoutEvent{
                    player,
                    amount: pot_portion,
                    game_id: object::uid_to_inner(&game.id),
                    hand_idx: game.hand_idx,
                    hand_bits,
                };
                debug::print(&payout_event);
                event::emit(payout_event);
                j = j + 1;
            };
            // return unused
            if (i == 0) {
                let j = 0;
                while (j < num_players) {
                    let player_bet = *vector::borrow(&game.cum_bets, (j as u64));
                    if (player_bet > pot_bet_amount) {
                        let unused = player_bet - pot_bet_amount;
                        let player_balance = vector::borrow_mut(&mut game.player_balances, (j as u64));
                        let new_player_balance = *player_balance + unused;
                        vector::push_back(&mut game.player_balances, new_player_balance);
                        vector::swap_remove(&mut game.player_balances, (j as u64));
                        let player = vector::borrow(&game.players, (j as u64));
                        let coin = coin::take(&mut game.pot, (unused as u64), ctx);
                        transfer::public_transfer(coin, *player);
                        debug::print(&unused);
                        debug::print(player);
                        debug::print(&pot_bet_amount);
                        let payout_event = PayoutEvent{
                            player: *player,
                            amount: unused,
                            game_id: object::uid_to_inner(&game.id),
                            hand_idx: game.hand_idx,
                            hand_bits: 0u64,
                        };
                        debug::print(&payout_event);
                        event::emit(payout_event);
                    };
                    j = j + 1;
                }
            };
            i = i + 1;
        };
    }

    public entry fun reset_game(game: &mut GameV2, _ctx: &mut TxContext) {
        assert!(game.hand_over, 0);
        game.shuffled = false;
        game.decrypt_round = 0;
        game.bet_round = 0;
        game.hand_over = false;
        game.can_add_player = true;
        game.current_hand_players = vector::empty();
        game.current_bets = vector::empty();
        game.current_has_bet = vector::empty();
        game.current_bet = 0;
        game.raise_amount = game.big_blind;
        game.sb_submitted = false;
        game.bb_submitted = false;
        game.deck = vector::empty();
        game.rounds = vector::empty();
        game.cum_bets = vector::empty();

        // rotate button
        let num_players = vector::length(&game.players);
        game.button_idx = (game.button_idx + 1) % (num_players as u8);

        event::emit(ResetEvent {
            game_id: object::uid_to_inner(&game.id),
            hand_idx: game.hand_idx,
        });
    }

    public fun new_betting_round(game: &mut GameV2, round_idx: u8) {
        let num_players = vector::length(&game.players);
        game.current_bets = vector::empty();
        game.current_has_bet = vector::empty();
        game.bet_round = round_idx;
        game.current_bet = 0;
        game.raise_amount = game.big_blind;
        let i = 0;
        while (i < num_players) {
            vector::push_back(&mut game.current_bets, 0);
            if (round_idx == 0) {
                vector::push_back(&mut game.cum_bets, 0);
            };
            i = i + 1;
        };
    }

    public entry fun bet(at: address, game_id: ID, hand_idx: u32, sui: Coin<SUI>, round: u8, bet_type: u8, ctx: &mut TxContext) {
        assert!((bet_type == BET_BET || bet_type == BET_CALL || bet_type == BET_BLIND_BET), 0);
        let value = (coin::value(&sui) as u256);
        let bet = Bet {
            id: object::new(ctx),
            coin: sui,
            game_id,
            hand_idx,
            player: tx_context::sender(ctx),
            amount: value,
            round,
            bet_type,
        };
        transfer::transfer(bet, at);
        event::emit(BetEvent {
            game_id: game_id,
            player: tx_context::sender(ctx),
            round: round,
            bet_type: bet_type,
            amount: value,
        });
    }

    public entry fun fold_and_decrypt_many(at: address, game_id: ID, hand_idx: u32, round: u8, decrypt_rounds: vector<u8>, all_input_bytes: vector<u8>, all_proof_bytes: vector<u8>, ctx: &mut TxContext) {
        decrypt_many(at, game_id, hand_idx, decrypt_rounds, all_input_bytes, all_proof_bytes, ctx);

        let fold = Betless {
            id: object::new(ctx),
            game_id,
            hand_idx,
            player: tx_context::sender(ctx),
            round,
            betless_type: BETLESS_FOLD,
        };
        transfer::transfer(fold, at);
        event::emit(FoldEvent {
            game_id: game_id,
            player: tx_context::sender(ctx),
            round: round,
        });
    }

    public entry fun fold(at: address, game_id: ID, hand_idx: u32, round: u8, ctx: &mut TxContext) {
        let fold = Betless {
            id: object::new(ctx),
            game_id,
            hand_idx,
            player: tx_context::sender(ctx),
            round,
            betless_type: BETLESS_FOLD,
        };
        transfer::transfer(fold, at);
        event::emit(FoldEvent {
            game_id: game_id,
            player: tx_context::sender(ctx),
            round: round,
        });
    }

    public entry fun check(at: address, game_id: ID, hand_idx: u32, round: u8, ctx: &mut TxContext) {
        let check = Betless {
            id: object::new(ctx),
            game_id,
            hand_idx,
            player: tx_context::sender(ctx),
            round,
            betless_type: BETLESS_CHECK,
        };
        transfer::transfer(check, at);
        event::emit(CheckEvent {
            game_id: game_id,
            player: tx_context::sender(ctx),
            round: round,
        });
    }

    public fun find_next_bet_player_this_round(game: &mut GameV2, curr_idx: u64, is_start: bool): bool {
        let num_players = vector::length(&game.players);
        let j = if (is_start)
            {0} 
        else 
            {1};
        while (j < num_players) {
            let i = ((curr_idx + j) % num_players);
            if (vector::contains(&game.current_hand_players, &(i as u8))) {
                let player_balance = *vector::borrow(&game.player_balances, i);
                if (player_balance == 0) {
                    j = j + 1;
                    continue
                };
                if (!vector::contains(&game.current_has_bet, &(i as u8))) {
                    game.bet_player = (i as u8);
                    return true
                };
                let current_player_bet = *vector::borrow(&game.current_bets, i);
                assert!(current_player_bet <= game.current_bet, 0);
                if (current_player_bet < game.current_bet) {
                    game.bet_player = (i as u8);
                    return true
                };
            };
            j = j + 1;
        };
        false
    }

    public fun find_next_bet_player(game: &mut GameV2, curr_idx: u64, is_start: bool, ctx: &mut TxContext) {
        // check if more betting required
        let k = 0;
        let num_players_remaning = vector::length(&game.current_hand_players);
        let num_players = vector::length(&game.players);

        assert!(num_players_remaning > 0, 0);
        if (num_players_remaning == 1) {
            // get winner
            game.bet_round = NUM_ROUNDS;
            let winner_idx = *vector::borrow(&game.current_hand_players, 0);
            let winner = *vector::borrow(&game.players, (winner_idx as u64));
            let pot_value = balance::value(&game.pot);
            let coin = coin::take(&mut game.pot, pot_value, ctx);
            transfer::public_transfer(coin, winner);

            let player_balance = vector::borrow_mut(&mut game.player_balances, (winner_idx as u64));
            let new_player_balance = *player_balance + (pot_value as u256);
            vector::push_back(&mut game.player_balances, new_player_balance);
            vector::swap_remove(&mut game.player_balances, (winner_idx as u64));

            let payout_event = PayoutEvent{
                player: winner,
                amount: (pot_value as u256),
                game_id: object::uid_to_inner(&game.id),
                hand_idx: game.hand_idx,
                hand_bits: 0u64,
            };
            game.hand_over = true;
            debug::print(&payout_event);
            event::emit(payout_event);
            return
        };

        let number_of_players_with_balance = 0;
        while (k < num_players_remaning) {
            let player_idx = *vector::borrow(&game.current_hand_players, k);
            let player_balance = *vector::borrow(&game.player_balances, (player_idx as u64));
            if (player_balance > 0) {
                number_of_players_with_balance = number_of_players_with_balance + 1;
            };
            k = k + 1;
        };

        let found_next = find_next_bet_player_this_round(game, curr_idx, is_start);
        if (!found_next) {
            let current_round = game.bet_round;
            new_betting_round(game, (current_round + 1));
            if (current_round == NUM_ROUNDS - 1) {
                return
            } else {
                if (number_of_players_with_balance < 2) {
                    game.bet_round = NUM_ROUNDS;
                    return
                };
                let sb_idx = (game.button_idx + 1) % (num_players as u8);
                let found_first = find_next_bet_player_this_round(game, (sb_idx as u64), true);
                if (!found_first) {
                    game.bet_round = NUM_ROUNDS;
                };
            };
        };

    }

    public entry fun add_betless(game: &mut GameV2, betless: Betless, ctx: &mut TxContext) {
        let Betless{id, game_id, hand_idx, player, round, betless_type} = betless;

        if (betless_type == BETLESS_FOLD) {
            event::emit(AddFoldEvent {
                game_id: game_id,
                player: player,
                round: (round as u8),
                hand_idx,
            });
        } else {
            event::emit(AddCheckEvent {
                game_id: game_id,
                player: player,
                round: (round as u8),
                hand_idx,
            });
        };

        assert!(hand_idx == game.hand_idx, 0);
        assert!(game_id == object::uid_to_inner(&game.id), 0);
        assert!(round == game.bet_round, 0);
        assert!(game.decrypt_round == game.bet_round + 1, 0);
        let (found, idx) = vector::index_of(&game.players, &player);
        assert!(found, 0);

        let (current_players_found, current_players_idx) = vector::index_of(&game.current_hand_players, &(idx as u8));
        assert!(current_players_found, 0);

        assert!(idx == (game.bet_player as u64), 0);
        assert!(vector::contains(&game.current_hand_players, &(idx as u8)), 0);
        assert!(game.sb_submitted && game.bb_submitted, 0);

        assert!((betless_type == BETLESS_FOLD) || (betless_type == BETLESS_CHECK), 0);
        if (betless_type == BETLESS_CHECK) {
            assert!(!vector::contains(&game.current_has_bet, &(idx as u8)), 0);
            vector::push_back(&mut game.current_has_bet, (idx as u8));
            let player_bet = *vector::borrow(&game.current_bets, idx);
            assert!((player_bet == game.current_bet), 0);
            // either bet is 0 or this is the big blind checking
            assert!((game.current_bet == 0) || ((game.bet_round == 0) && (player_bet == game.big_blind)), 0);
        } else {
            // fold
            vector::remove(&mut game.current_hand_players, current_players_idx);
        };

        let player_balance = *vector::borrow(&game.player_balances, idx);
        assert!(player_balance > 0, 0);

        find_next_bet_player(game, idx, false, ctx);
        object::delete(id);

    }

    public entry fun return_bet(bet: Bet, _ctx: &mut TxContext) {
        let Bet{id, coin, game_id: _game_id, hand_idx: _hand_idx, player, amount: _amount, round: _round, bet_type: _bet_type} = bet;
        transfer::public_transfer(coin, player);
        object::delete(id);
    }

    public entry fun add_bet(game: &mut GameV2, bet: Bet, ctx: &mut TxContext) {
        let Bet{id, coin, game_id, hand_idx, player, amount: _amount, round, bet_type} = bet;
        assert!(hand_idx == game.hand_idx, 0);
        assert!(game_id == object::uid_to_inner(&game.id), 0);
        assert!(round == game.bet_round, 0);
        let (found, idx) = vector::index_of(&game.players, &player);
        assert!(found, 0);
        assert!(vector::contains(&game.current_hand_players, &(idx as u8)), 0);

        let coin_balance = coin::into_balance(coin);
        let bet_value = balance::value(&coin_balance);
        // add bet to pot
        balance::join(&mut game.pot, coin_balance);

        // update player balance
        let player_balance = *vector::borrow(&game.player_balances, idx);
        assert!(player_balance >= (bet_value as u256), 0);
        let new_player_balance = player_balance - (bet_value as u256);
        vector::push_back(&mut game.player_balances, new_player_balance);
        vector::swap_remove(&mut game.player_balances, idx);

        // check all-in
        let player_is_all_in = (new_player_balance == 0);
        let current_player_bet = *vector::borrow(&game.current_bets, idx);

        // update bet
        let total_bet_value = (bet_value as u256) + current_player_bet;
        vector::push_back(&mut game.current_bets, total_bet_value);
        vector::swap_remove(&mut game.current_bets, idx);

        //update cum bet
        let previous_cum_bet = *vector::borrow(&game.cum_bets, idx);
        let new_cum_bet = previous_cum_bet + (bet_value as u256);
        vector::push_back(&mut game.cum_bets, new_cum_bet);
        vector::swap_remove(&mut game.cum_bets, idx);

        let is_raise = false;

        // blinds
        if ((game.bet_round == 0) && (game.decrypt_round == 0)) {
            assert!(bet_type == BET_BLIND_BET, 0);
            assert!(current_player_bet == 0, 0);
            let num_players = (vector::length(&game.players) as u8);
            //blinds
            let (sb_idx, bb_idx) = if (num_players == 2) {
                ((((0 + game.button_idx) % num_players) as u64), (((1 + game.button_idx) % num_players) as u64))
            } else {
                ((((1 + game.button_idx) % num_players) as u64), (((2 + game.button_idx) % num_players) as u64))
            };
            assert!(idx == sb_idx || idx == bb_idx, 0);
            if (idx == sb_idx) {
                assert!(!game.sb_submitted, 0);
                game.sb_submitted = true;
                assert!(bet_value == (game.small_blind as u64), 0);
            } else if (idx == bb_idx) {
                assert!(!game.bb_submitted, 0);
                game.bb_submitted = true;
                assert!(bet_value == (game.big_blind as u64), 0);
                game.current_bet = (bet_value as u256);
                game.raise_amount = (bet_value as u256);
            };
            game.bet_player = (game.bet_player + 1) % num_players;
        } else {
            assert!(idx == (game.bet_player as u64), 0);
            assert!(game.decrypt_round == game.bet_round + 1, 0);
            if (!vector::contains(&game.current_has_bet, &(idx as u8))) {
                vector::push_back(&mut game.current_has_bet, (idx as u8));
            };
            if (bet_type == BET_BET) {
                assert!((total_bet_value > game.current_bet), 0);
                if (game.current_bet > 0) {
                    is_raise = true;
                };
                let raise_amount = total_bet_value - game.current_bet;
                if (!player_is_all_in) {
                    assert!(raise_amount >= game.raise_amount, 0);
                };
                game.raise_amount = raise_amount;
                game.current_bet = total_bet_value;
            } else {
                assert!(bet_type == BET_CALL, 0);
                assert!((total_bet_value == game.current_bet) || (player_is_all_in && (total_bet_value < game.current_bet)), 0);
            };
        };
        find_next_bet_player(game, idx, false, ctx);
        object::delete(id);
        event::emit(AddBetEvent {
            game_id: object::uid_to_inner(&game.id),
            hand_idx,
            player,
            amount: (bet_value as u256),
            total_amount: (total_bet_value as u256),
            round,
            bet_type,
            is_raise
        });
    }

    #[test]
    fun test_shuffle() {
        use sui::test_scenario;
        // create test addresses representing users
        let admin = @0xBABE;
        let p1 = @0xCAFE;
        let p2 = @0xFACE;
        // let p3 = @0xFEED;
        // let p4 = @0xBEEF;

        //init
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };

        // new game
        test_scenario::next_tx(scenario, p1);
        let game_id = 
        {
            let ctx = test_scenario::ctx(scenario);
            let _asdf = create_game2(admin, 1, 2, ctx);
            let game_id = object::id_from_address(tx_context::last_created_object_id(ctx));
            game_id
        };

        let test_pk = vector<u8>[101, 199, 55, 88, 112, 204, 123, 216, 66, 152, 66, 78, 88, 132, 137, 133, 19, 226, 38, 193, 173, 146, 96, 208, 73, 83, 12, 221, 226, 73, 196, 47, 129, 165, 193, 219, 139, 155, 214, 147, 133, 215, 14, 113, 97, 222, 110, 101, 69, 161, 35, 28, 225, 224, 37, 222, 59, 218, 241, 19, 238, 96, 176, 41];
        let test_pk_proof = vector<u8>[93,38,149,114,231,176,43,47,107,27,107,135,160,84,189,74,223,40,140,101,38,159,132,111,150,90,160,7,150,25,44,3,113,218,167,136,88,80,101,154,248,116,2,139,237,109,191,8,198,93,22,43,249,20,44,224,3,48,60,131,235,107,188,3,173,17,242,129,15,184,181,170,226,246,147,148,143,52,178,93,170,243,73,6,217,196,91,236,4,154,85,226,52,197,177,47,149,66,114,126,76,233,5,254,180,251,126,238,140,10,60,252,115,196,164,246,47,21,225,97,190,145,186,210,105,11,235,46];

        // p1 join
        test_scenario::next_tx(scenario, p1);
        let p1_public_key = 
        {
            let ctx = test_scenario::ctx(scenario);
            join(admin, game_id, test_pk, test_pk_proof, 40, 0, ctx);
            let pk_id = object::id_from_address(tx_context::last_created_object_id(ctx));
            pk_id
        };

        // p2 join
        test_scenario::next_tx(scenario, p2);
        let p2_public_key = 
        {
            let ctx = test_scenario::ctx(scenario);
            join(admin, game_id, test_pk, test_pk_proof, 40, 1, ctx);
            let pk_id = object::id_from_address(tx_context::last_created_object_id(ctx));
            pk_id
        };


        let test_add_p1 = vector<u8>[2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,101,199,55,88,112,204,123,216,66,152,66,78,88,132,137,133,19,226,38,193,173,146,96,208,73,83,12,221,226,73,196,47,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,101,199,55,88,112,204,123,216,66,152,66,78,88,132,137,133,19,226,38,193,173,146,96,208,73,83,12,221,226,73,196,47,129,165,193,219,139,155,214,147,133,215,14,113,97,222,110,101,69,161,35,28,225,224,37,222,59,218,241,19,238,96,176,41];
        let test_add_p1_proof = vector<u8>[185,171,68,223,14,44,4,185,131,239,192,255,86,134,80,103,59,67,77,39,197,229,3,5,3,21,169,160,237,88,212,131,2,64,225,64,93,139,149,104,255,46,198,6,254,251,57,21,3,228,233,163,209,170,199,220,254,73,150,53,151,130,255,15,71,219,117,223,250,135,11,223,55,221,221,171,16,212,104,232,7,25,234,228,152,101,72,58,236,93,141,148,179,165,226,163,52,88,196,231,138,33,171,13,158,20,93,43,102,122,110,240,50,105,52,12,24,10,181,83,101,84,9,7,237,4,189,2];
        let test_add_p2 = vector<u8>[3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,101,199,55,88,112,204,123,216,66,152,66,78,88,132,137,133,19,226,38,193,173,146,96,208,73,83,12,221,226,73,196,47,101,199,55,88,112,204,123,216,66,152,66,78,88,132,137,133,19,226,38,193,173,146,96,208,73,83,12,221,226,73,196,47,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,174,131,154,146,122,159,21,189,81,23,112,150,201,12,32,241,207,160,200,40,127,186,60,221,236,88,93,240,197,244,3,4,15,84,99,224,49,192,152,48,37,46,179,94,169,203,125,202,172,181,32,106,158,163,198,184,172,124,192,63,61,166,194,12];
        let test_add_p2_proof = vector<u8>[206,179,153,238,109,234,38,243,166,193,199,189,9,245,12,22,150,14,12,12,89,104,123,254,27,82,66,245,32,134,17,135,165,218,139,13,166,217,173,233,113,250,19,54,84,21,143,220,194,178,179,111,18,108,229,253,3,36,220,57,190,242,83,36,65,141,65,147,249,248,211,131,107,87,122,164,226,107,93,208,37,162,255,55,88,115,105,250,110,35,51,70,38,231,91,140,73,47,107,28,99,156,53,228,137,200,107,199,52,171,238,223,125,10,128,137,18,9,137,192,152,220,53,226,101,165,19,30];

        // add player 1
        test_scenario::next_tx(scenario, admin);
        {
            let game = test_scenario::take_from_sender_by_id<GameV2>(scenario, game_id);
            let public_key = test_scenario::take_from_sender_by_id<JoinGame>(scenario, p1_public_key);
            let ctx = test_scenario::ctx(scenario);
            add_player2(&mut game, public_key, test_add_p1, test_add_p1_proof, ctx);
            test_scenario::return_to_sender(scenario, game);
        };

        // add player 2
        test_scenario::next_tx(scenario, admin);
        {
            let game = test_scenario::take_from_sender_by_id<GameV2>(scenario, game_id);
            let public_key = test_scenario::take_from_sender_by_id<JoinGame>(scenario, p2_public_key);
            let ctx = test_scenario::ctx(scenario);
            add_player2(&mut game, public_key, test_add_p2, test_add_p2_proof, ctx);
            test_scenario::return_to_sender(scenario, game);
        };

        test_scenario::next_tx(scenario, p1);
        {
            let decrypt_inputs = vector<u8>[2,192,1,101,199,55,88,112,204,123,216,66,152,66,78,88,132,137,133,19,226,38,193,173,146,96,208,73,83,12,221,226,73,196,47,129,165,193,219,139,155,214,147,133,215,14,113,97,222,110,101,69,161,35,28,225,224,37,222,59,218,241,19,238,96,176,41,19,177,146,147,90,253,16,246,78,38,129,119,243,10,158,243,71,233,109,44,24,68,165,131,168,16,70,78,227,236,107,14,166,18,198,7,110,241,87,61,115,22,16,3,38,110,108,168,63,171,103,238,196,59,69,237,192,229,154,202,198,32,32,40,68,232,190,153,220,37,133,170,3,243,28,96,105,60,135,63,122,127,153,232,212,213,208,197,171,151,195,247,95,16,118,18,221,5,230,61,147,151,161,145,50,212,146,14,183,179,96,23,175,120,13,51,8,108,45,128,253,63,104,243,77,37,13,43,192,1,101,199,55,88,112,204,123,216,66,152,66,78,88,132,137,133,19,226,38,193,173,146,96,208,73,83,12,221,226,73,196,47,129,165,193,219,139,155,214,147,133,215,14,113,97,222,110,101,69,161,35,28,225,224,37,222,59,218,241,19,238,96,176,41,21,224,241,174,117,62,6,189,151,201,179,172,209,15,194,68,153,111,46,252,61,174,59,186,229,53,42,130,211,25,152,0,213,137,32,1,198,127,13,9,36,149,184,79,29,153,106,188,187,34,60,38,204,68,21,18,37,147,55,218,12,236,44,11,247,191,112,84,69,147,162,136,112,39,239,103,94,15,75,190,168,108,152,194,47,44,243,39,42,202,56,201,225,122,24,25,100,204,165,177,23,69,180,194,116,50,221,4,183,209,42,127,193,144,185,5,152,49,62,178,227,99,30,92,85,175,162,1];
            let decrypt_proof = vector<u8>[2,128,1,24,121,87,248,82,12,209,25,233,100,69,84,87,95,97,137,224,157,192,97,27,84,113,155,96,158,76,58,105,60,201,152,43,185,148,249,138,147,34,34,90,9,222,227,1,72,195,160,24,121,162,125,44,155,97,180,5,233,127,210,56,41,110,18,41,201,224,176,108,65,85,232,111,61,181,225,212,62,38,71,207,240,217,142,0,82,137,190,76,132,61,143,243,68,107,164,123,198,22,145,182,114,183,22,175,161,237,213,46,91,176,219,80,210,239,189,171,58,247,40,152,93,130,216,36,121,101,8,128,1,37,90,22,192,80,162,116,182,144,156,10,151,214,125,244,161,251,146,18,231,241,255,35,9,118,104,6,138,83,156,97,155,254,231,27,133,199,25,105,47,154,85,223,152,144,223,88,242,77,42,25,247,6,70,125,82,42,175,192,169,93,87,217,45,184,188,213,208,220,75,83,210,28,3,124,115,13,141,24,43,124,31,35,237,69,28,87,160,125,14,50,193,153,206,250,47,104,63,179,56,42,41,162,17,58,236,171,255,116,68,94,12,123,236,137,246,185,119,217,119,96,253,158,39,155,1,118,5];
            let ctx = test_scenario::ctx(scenario);
            decrypt2(admin, game_id, 0, 0, false, decrypt_inputs, decrypt_proof, ctx);
        };

        test_scenario::end(scenario_val);
    }
}