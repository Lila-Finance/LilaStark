
// Intro: This is Lila Protocol, a rate swap protocol yielding users what they want the most
// Author: @0xrishabh
// Functions:
//     * create_order: Called by any user to set their terms for order
//     * fullfill_order: Called by the user who wants to fill an order
//     * get_order: Returns all the info about the order and it's status

// mod interfaces;
// use interfaces::IZKlend::{
//     IZKlend
// };
use starknet::contract_address_const;
use starknet::ContractAddress;
#[derive(Copy, Drop, Serde, starknet::Store)]
struct OrderParams {
    filled: bool,
    strategy: u8,
    amount: felt252,
    interest: felt252,
    term_time: felt252,
    filled_time: felt252,
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
    fn create_order(ref self: TContractState, amount: felt252, interest: felt252, term_time: felt252, strategy: u8);
    fn fullfill_order(ref self: TContractState, id: felt252);
    fn withdraw(ref self: TContractState, id: felt252);
    fn get_order(self: @TContractState, id: felt252) -> lila_on_starknet::OrderParams;
}

#[starknet::contract]
mod Order {
    use starknet::ContractAddress;
    use starknet::get_block_timestamp;
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Metadata, ERC20ABIDispatcher, ERC20ABIDispatcherTrait, IERC20Dispatcher
    };
    use core::poseidon::PoseidonTrait;
    use core::hash::{HashStateTrait, HashStateExTrait};

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
            amount: felt252,
            interest: felt252,
            term_time: felt252,
            strategy: u8
        ){
            let token_address = self.strategy.read(strategy).token;
            let token = IERC20Dispatcher {contract_address: token_address};
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
                maker: ContractAddress.zero(),

            };
            let nonce = self.nonce.read();
            let id = PoseidonTrait::new().update(order.user.into()).update(nonce.into()).finalize();

            self.orders.write(id, order);
            self.nonce.write(nonce+1);

        }

        fn fullfill_order(ref self: ContractState, id: felt252){
            // let order = self.orders.read(id);
            // let strategy = self.strategy.read(order.strategy);
            // let interest_amount = order.amount * order.interest;
            // let token_address = strategy.token;
            // let token = IERC20Dispatcher {contract_address: token_address};
            // token.transferFrom(
            //     starknet::get_caller_address(),
            //     starknet::get_contract_address(),
            //     interest_amount
            // );

            // // Integrating ZkLend
            // let zklend = IZKlend{ strategy.protocol };
            // token.approve(strategy.protocol, order.amount);
            // zklend.deposit(token, order.amount);
        }

        fn withdraw(ref self: ContractState, id:felt252){
            // let order = self.order.read(id);
            // assert(
            //     order.maker == starknet::get_caller_address() ||
            //     order.filled_time - get_block_timestamp() >= order.term_time,
            //     true
            // );
        }

        fn get_order(self: @ContractState, id: felt252) -> lila_on_starknet::OrderParams {
            self.orders.read(id)
        }


    }
}
