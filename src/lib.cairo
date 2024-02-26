// Intro: This is Lila Protocol, a rate swap protocol yielding users what they want the most
// Author: @0xrishabh
// Functions:
//     * create_order: Called by any user to set their terms for order
//     * fullfill_order: Called by the user who wants to fill an order
//     * get_order: Returns all the info about the order and it's status

mod mocks;
#[cfg(test)]
mod tests;
use core::fmt::{Display, Formatter, Error};
mod zklend;
use starknet::ContractAddress;
#[derive(Copy, Drop, Serde, starknet::Store)]
struct OrderParams {
    filled: bool,
    strategy: felt252,
    amount: felt252,
    interest: u256,
    term_time: u64,
    filled_time: u64,
    user: ContractAddress,
    maker: ContractAddress,
}
// impl OrderParamsDisplay of Display<OrderParams> {
//     fn fmt(self: @OrderParams, ref f: Formatter) -> Result<(), Error> {
//         let amount = *self.amount;
//         let interest = *self.interest;
//         let term_time = *self.term_time;
//         let user = *self.user;
//         return writeln!(f, "Order ({amount}, {interest}, {term_time})");
//     }
// }

#[derive(Copy, Drop, Serde, starknet::Store)]
struct StrategyInfo {
    token: ContractAddress,
    protocol: ContractAddress,
}

#[starknet::interface]
trait ILila<TContractState> {
    fn create_order(
        ref self: TContractState, amount: felt252, interest: u256, term_time: u64, strategy: felt252
    );
    fn fulfill_order(ref self: TContractState, id: felt252);
    fn withdraw(ref self: TContractState, id: felt252);
    fn get_nonce(self: @TContractState, user: ContractAddress) -> u64;
    fn get_order(self: @TContractState, id: felt252) -> lila_on_starknet::OrderParams;
    fn get_order_user(self: @TContractState, user: ContractAddress, nonce: u64) -> lila_on_starknet::OrderParams;
    fn get_strategy(self: @TContractState, id: felt252) -> lila_on_starknet::StrategyInfo;
    fn set_strategy (ref self: TContractState, token: ContractAddress, protocol: ContractAddress);
}

#[starknet::contract]
mod Lila {
    use core::traits::Into;
    use starknet::ContractAddress;
    use starknet::get_block_timestamp;
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Metadata, ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Dispatcher
    };
    use core::poseidon::PoseidonTrait;
    use core::hash::{HashStateTrait, HashStateExTrait};
    use lila_on_starknet::zklend;
    use lila_on_starknet::zklend::{IZklendMarketDispatcher, IZklendMarketDispatcherTrait};

    #[storage]
    struct Storage {
        orders: LegacyMap::<felt252, lila_on_starknet::OrderParams>,
        strategy: LegacyMap::<felt252, lila_on_starknet::StrategyInfo>,
        nonce: LegacyMap::<ContractAddress, u64>,
        total_strategy: u64
    }

    #[abi(embed_v0)]
    impl LilaImpl of super::ILila<ContractState> {
        // * Transfer tokens from the user to the contract
        // * Make Assertions:
        //      * The amount transfered is same as order amount
        //      *
        // * Save the order of the user
        // * Emit the event for the indexers and frontend
        fn create_order(
            ref self: ContractState, amount: felt252, interest: u256, term_time: u64, strategy: felt252
        ) {
            let u256_amount: u256 = amount.into();
            let token_address = self.strategy.read(strategy).token;
            let token = ERC20ABIDispatcher { contract_address: token_address };
            let user = starknet::get_caller_address();
            // allow transfer
            token.transferFrom(user, starknet::get_contract_address(), u256_amount);

            let order = lila_on_starknet::OrderParams {
                amount,
                interest,
                strategy: strategy,
                term_time: term_time,
                filled: false,
                filled_time: 0,
                user: user,
                maker: starknet::contract_address_const::<0>(),
            };

            let nonce = self.nonce.read(user);
            let id = PoseidonTrait::new().update(order.user.into()).update(nonce.into()).finalize();

            self.orders.write(id, order);
            self.nonce.write(user, nonce + 1);

        }

        fn fulfill_order(ref self: ContractState, id: felt252) {
            let mut order = self.orders.read(id);
            let strategy = self.strategy.read(order.strategy);
            let interest_amount = order.amount.into() * order.interest / 100;
            let token_address = strategy.token;
            let token = ERC20ABIDispatcher { contract_address: token_address };
            token
                .transferFrom(
                    starknet::get_caller_address(),
                    starknet::get_contract_address(),
                    interest_amount
                );
            token.approve(strategy.protocol, order.amount.into());

            // Integrating ZkLend

            let zklend = IZklendMarketDispatcher { contract_address: strategy.protocol };
            zklend.deposit(token: token.contract_address, amount: order.amount);

            order.filled = true;
            order.filled_time = get_block_timestamp();
            order.maker = starknet::get_caller_address();
            self.orders.write(id, order);
        }

        fn set_strategy(ref self: ContractState, token: starknet::ContractAddress,  protocol: starknet::ContractAddress) {

            let strategy = lila_on_starknet::StrategyInfo {
                token,
                protocol
            };

            let total_strategy = self.total_strategy.read();
            self.strategy.write(total_strategy.into(), strategy);
            self.total_strategy.write(total_strategy + 1);
        }

        fn withdraw(ref self: ContractState, id: felt252) {
            let order = self.orders.read(id);
            let strategy = self.strategy.read(order.strategy);

            assert!(
                order.maker == starknet::get_caller_address() ||
                get_block_timestamp() - order.filled_time >= order.term_time
            );

            let token = ERC20ABIDispatcher { contract_address: strategy.token };
            let zklend = IZklendMarketDispatcher { contract_address: strategy.protocol };
            let this = starknet::get_contract_address();

            let balance_before = token.balanceOf(this);
            zklend.withdraw_all(token: strategy.token);
            let balance_after = token.balanceOf(this);

            // After withdraw: oldFunds + order.amount + interest
            // Edge Case: if the funds are withdrawn too early,
            // then we will recieve order.amount - zklend fee

            let mut profit = 0;
            let balance_diff = balance_after - balance_before;
            if balance_diff > order.amount.into() {
                profit = balance_diff - order.amount.into()
            }

            let interest_amount = order.amount.into() * order.interest / 100;

            token.transfer(order.user, order.amount.into() + interest_amount);
            if profit > 0 {
                token.transfer(order.maker, profit);
            }

        }

        fn get_strategy(self: @ContractState, id: felt252) -> lila_on_starknet::StrategyInfo {
            self.strategy.read(id)
        }

        fn get_order(self: @ContractState, id: felt252) -> lila_on_starknet::OrderParams {
            self.orders.read(id)
        }

        fn get_order_user(self: @ContractState, user: ContractAddress, nonce: u64) -> lila_on_starknet::OrderParams{
            let id = PoseidonTrait::new().update(user.into()).update(nonce.into()).finalize();
            self.orders.read(id)
        }

        fn get_nonce(self: @ContractState, user: ContractAddress) -> u64 {
            self.nonce.read(user)
        }
    }
}

//wrapper on each protocol
