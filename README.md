# Cross-Chain Rebase Token

1. Create protocol that allows user to deposit into a Vault and in return, receive rebase tokens that represents their underlying balance.
2. Rebase token -> balanceOf is dynamic to show the increasing balance with time
    - the balance increases linearly with time
    - mint tokens to our users everytime they perfom an action (minting, burning, transferring, bridging, etc)
3. Intrese rate
    - individually set an interest rate per each user based on some global interest rate at the time the user deposit into the vault
    - this global interest rate can only decrease to incentives/reward early adoptors.
    - increase token adoption
