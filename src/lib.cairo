
// Intro: This is Lila Protocol, a rate swap protocol yielding users what they want the most
// Author: @0xrishabh
// Functions:
//     * create_order: Called by any user to set their terms for order
//     * fullfill_order: Called by the user who wants to fill an order
//     * get_order: Returns all the info about the order and it's status


mod zklend;

use starknet::ContractAddress;
#[derive(Copy, Drop, Serde, starknet::Store)]
struct OrderParams {
    filled: bool,
    strategy: u8,
    amount: u256,
    interest: u256,
    term_time: u64,
    filled_time: u64,
    user: ContractAddress,
    maker: ContractAddress,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct StrategyInfo {
   token: ContractAddress,
   protocol: ContractAddress,
}

#[starknet::interface]
trait IOrder<TContractState> {
    fn create_order(ref self: TContractState, amount: u256, interest: u256, term_time: u64, strategy: u8);
    fn fullfill_order(ref self: TContractState, id: felt252);
    fn withdraw(ref self: TContractState, id: felt252);
    fn get_order(self: @TContractState, id: felt252) -> lila_on_starknet::OrderParams;
}

#[starknet::contract]
mod Order {
    use starknet::get_block_timestamp;
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Metadata, ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Dispatcher
    };
    use core::poseidon::PoseidonTrait;
    use core::hash::{HashStateTrait, HashStateExTrait};
    use lila_on_starknet::zklend;
    use lila_on_starknet::zklend::{ IZklendMarketDispatcher, IZklendMarketDispatcherTrait };

    #[storage]
    struct Storage {
        // id ==> OrderParams
        orders: LegacyMap::<felt252, lila_on_starknet::OrderParams>,
        strategy: LegacyMap::<u8, lila_on_starknet::StrategyInfo>,
        nonce: u64,
    }

    #[abi(embed_v0)]
    impl OrderImpl of super::IOrder<ContractState> {
        // TODO:
        // * Transfer tokens from the user to the contract
        // * Make Assertions:
        //      * The amount transfered is same as order amount
        //      *
        // * Save the order of the user
        // * Emit the event for the indexers and frontend
        fn create_order(
            ref self: ContractState,
            amount: u256,
            interest: u256,
            term_time: u64,
            strategy: u8
        ){
            let token_address = self.strategy.read(strategy).token;
            let token = ERC20ABIDispatcher {contract_address: token_address};
            let user = starknet::get_caller_address();
            token.transferFrom(
                user,
                starknet::get_contract_address(),
                amount
            );

            let order = lila_on_starknet::OrderParams{
                amount: amount,
                interest: interest,
                strategy: strategy,
                term_time: term_time,
                filled: false,
                filled_time: 0,
                user: user,
                maker: starknet::contract_address_const::<0x0>(),
            };

            let nonce = self.nonce.read();
            let id = PoseidonTrait::new().update(order.user.into()).update(nonce.into()).finalize();

            self.orders.write(id, order);
            self.nonce.write(nonce+1);

        }

        fn fullfill_order(ref self: ContractState, id: felt252){
            let order = self.orders.read(id);
            let strategy = self.strategy.read(order.strategy);
            let interest_amount = order.amount * order.interest;
            let token_address = strategy.token;
            let token = ERC20ABIDispatcher {contract_address: token_address};
            token.transferFrom(
                starknet::get_caller_address(),
                starknet::get_contract_address(),
                interest_amount
            );
            token.approve(strategy.protocol, order.amount);

            // Integrating ZkLend

            let zklend = IZklendMarketDispatcher{ contract_address: strategy.protocol };
            zklend.deposit(token, order.amount);
        }

        fn withdraw(ref self: ContractState, id:felt252){
            let order = self.orders.read(id);
            assert(
                order.maker == starknet::get_caller_address() ||
                order.filled_time - get_block_timestamp() >= order.term_time,
                0
            );
        }

        fn get_order(self: @ContractState, id: felt252) -> lila_on_starknet::OrderParams {
            self.orders.read(id)
        }


    }
}
