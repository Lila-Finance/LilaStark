use starknet::ContractAddress;

#[starknet::interface]
trait IZKlend<TContractState> {
    fn deposit(ref self: TContractState, token: ContractAddress, amount: felt252);
    fn withdraw_all(ref self: TContractState, token: ContractAddress);
}
