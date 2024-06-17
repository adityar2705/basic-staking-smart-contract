// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

//interface to interact with the ERC20 -> staking and reward tokens
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool);
}

//staking smart contract
contract Staking{
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;

    address public owner;

    //details of the reward by the owner 
    uint public duration;
    uint public finishAt;
    uint public updatedAt;
    uint public rewardRate;
    uint public rewardPerTokenStored;

    //keeping track of the ongoing dynamic rewards per token for each user
    mapping(address => uint) public userRewardPerTokenPaid;

    //rewards that users have earned
    mapping(address => uint) public rewards;

    //supply of all the staking token
    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    modifier onlyOwner(){
        require(msg.sender == owner,"Only owner can call this function.");
        _;
    }

    //modifier to keep track of updating rewards per token
    modifier updateRewards(address _account){
        rewardPerTokenStored = rewardsPerToken();
        updatedAt = block.timestamp > finishAt ? finishAt : block.timestamp;

        //update the user reward
        if(_account != address(0)){
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _stakingToken, address _rewardsToken){
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    //function to set th rewards
    function setRewardsDuration(uint _duration) external onlyOwner{
        require(block.timestamp > finishAt,"Reward duration not finished.");
        duration = _duration;
    }

    //set the reward rate and send rewards to the smart contract -> we pass address(0) since the owner doesnt earn rewards -> we only modify the reward per token stored
    function notifyRewardAmount(uint _amount) external updateRewards(address(0)){
        //setting the reward rate after the duration has expired
        if(block.timestamp > finishAt){
            rewardRate = _amount/duration;
        }
        else{
            //setting the reward rate in the middle of the duration
            uint remainingRewards = rewardRate * (finishAt - block.timestamp);
            rewardRate = (_amount + remainingRewards)/duration;
        }

        require(rewardRate > 0, "Reward rate is 0.");
        
        //make sure enough reward tokens are there in the smart contract
        require(rewardRate * duration <= rewardsToken.balanceOf(address(this)),"There are not enough reward tokens.");

        //setting the new finishAt
        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
    }

    //allowing users to stake their tokens
    function stake(uint _amount) external updateRewards(msg.sender){
        require(_amount > 0,"No staking tokens supplied.");
        stakingToken.transferFrom(msg.sender, address(this), _amount);

        //updating the user balance and total supply
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
    }

    //allowing users to withdraw the staked tokens
    function withdraw(uint _amount) external updateRewards(msg.sender){
        require(_amount > 0, "Specify a withdrawal amount.");
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        stakingToken.transfer(msg.sender, _amount);
    }

    //calculate the rewards per token staked
    function rewardsPerToken() public view returns(uint){
        if(totalSupply == 0){
            return rewardPerTokenStored;
        }
        else{
            //this will return the per token reward rate
            if(block.timestamp > finishAt){
                return rewardPerTokenStored + (rewardRate*(finishAt - updatedAt)*1e18)/totalSupply;
            }
            else{
                return rewardPerTokenStored + (rewardRate*(block.timestamp - updatedAt)*1e18)/totalSupply;
            }
        }
    }

    //calculates the rewards earned by a particular account
    function earned(address _account) public view returns(uint){
        //scaling down the number by 10^18 due to decimal representation
        return (balanceOf[_account]*(rewardsPerToken() - userRewardPerTokenPaid[_account]))/1e18
        + rewards[_account];
    }

    //function for user to actually get the reward token
    function getReward() external{
        uint reward = rewards[msg.sender];

        if(reward > 0){
            rewards[msg.sender] = 0;
            rewardsToken.transfer(msg.sender, reward);
        }
    }
}
