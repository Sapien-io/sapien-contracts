export const advanceTime = async (time) => {
    await ethers.provider.send("evm_increaseTime", [time]) // add 10 seconds
    await ethers.provider.send("evm_mine", []) // 
}

