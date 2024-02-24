use starknet::ContractAddress;

#[starknet::interface]
trait IZklendMarket<TContractState> {
    fn get_total_debt_for_token(self: @TContractState, token: ContractAddress) -> felt252;
    fn deposit(ref self: TContractState, token: ContractAddress, amount: felt252);
    fn withdraw(ref self: TContractState, token: ContractAddress, amount: felt252);
}
