// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

/*
devGaangs v1.0
Quentin for FrAaction Gangs
*/

contract devGaangs {

    // State Transitions:
    //   (1) INACTIVE on deploy
    //   (2) ACTIVE on initiateMerger() and voteForMerger(), ASSETSTRANSFERRED on voteForMerger()
    //   (3) MERGED or POSTMERGERLOCKED on finalizeMerger()
    enum JobStatus { 
        INACTIVE, 
        FUNDING,
        APPOINTING,
        WORKING,
        CANCELLED,
        FINALIZED
    }

    // IERC20Upgradeable(_asset).approve(aavePoolContract, _amount);

    function proposeFundingNewJob(
        uint256 _rewardAmount,
        uint256 _amount,
        uint256 _share,
        uint256 _tokenAddress,
        uint256 _apppointedGaang,
        address _appointedDev
    ) public payable {
        require(
            _share <= 1000, 
            "proposeFundingNewJob: wrong shared tokens parameter"
        );
        jobId++;
        uint256 contribution;
        if (msg.value > 0) {
            require(
                _tokenAddress == address(0), 
                "proposeFundingNewJob: wrong token address parameter"
            );
            
            contribution = msg.value;
        } else if (_amount > 0) {
            multiTokenTransferFunction(_tokenAddress, msg.sender, address(this), _amount);
            jobFundingToken[jobId] = _tokenAddress;
            contribution = _amount;
        } else { 
            return;
        }
        if (_apppointedGaang != 0 || _appointedDev != address(0)) {
            if (appointedDev[jobId] != address(0)) {
                appointedDev[jobId] = _appointedDev;
            } else {
                appointedGaang[jobId] = _apppointedGaang;
            }
        }
        if (jobRewardAmount[jobId] > contribution) {
            jobStatus[jobId] = JobStatus.APPOINTING;
        } else {
            jobStatus[jobId] = JobStatus.FUNDING;
        }
        collectiveJobFunding[jobId] = true;
        fundingDeadline[jobId] = block.timestamp + numberFundingDays * 1 days;
        jobManager[jobId] = msg.sender;
        contributedToJobReward[jobId] += contribution;
        userContributionToJobReward[jobId][msg.sender] += contribution;
        jobRewardAmount[jobId] = _rewardAmount;
        shareTodevOrGaang[jobId] = _share;
        emit ProposedFundingNewJob(jobId, _rewardAmount, contribution);
    }

    function contributeFundingNewJob(
        uint256 _jobId,
        address _tokenAddress,
        uint256 _amount
    ) external payable {
        require(
            block.timestamp <= fundingDeadline[_jobId], 
            "contributeFundingNewJob: funding deadline expired"
        );
        require(
            jobFundingToken[_jobId] == _tokenAddress, 
            "contributeFundingNewJob: wrong funding token address"
        );
        if (jobStatus[_jobId] == JobStatus.EXTRAFUNDING) updateUserContributionBalance(_jobId, msg.sender);
        uint256 contribution;
        if (msg.value > 0) {
            require(
                jobFundingToken[_jobId] == address(0), 
                "contributeFundingNewJob: wrong funding token address"
            );
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            contribution = msg.value;
        } else if (_amount > 0 && _tokenAddress == jobFundingToken[_jobId]) {
            multiTokenTransferFunction(_tokenAddress, msg.sender, address(this), _amount);
            contribution = _amount;
        } else { 
            return;
        }
        contributedToJobReward[_jobId] += contribution;
        userContributionToJobReward[_jobId][msg.sender] += contribution;
        if (contributedToJobReward[_jobId] >= jobRewardAmount[_jobId]) {
            if (jobStatus[_jobId] == JobStatus.FUNDING) {
                jobStatus[_jobId] = JobStatus.APPOINTING;
            } else {
                jobStatus[_jobId] = JobStatus.WORKING;
            }
        }
        emit ContributedFundingNewJob(_jobId, contribution, jobStatus[_jobId]);
    }

    function updateFundingNewJob(
        uint256 _jobId,
        uint256 _updatedReward
    ) external {
        require(
            collectiveJobFunding[_jobId], 
            "updateFundingNewJob: must be active job funding"
        );
        require(
            block.timestamp <= fundingDeadline[_jobId], 
            "updateFundingNewJob: funding deadline expired"
        );
        require(
            jobManager[_jobId] == msg.sender, 
            "updateFundingNewJob: must be the job initiator"
        );
        require(
            _updatedReward >= contributedToJobReward[_jobId], 
            "updateFundingNewJob: must be greater than already collected funds for the job reward"
        );
        jobRewardAmount[_jobId] = _updatedReward;
        emit UpdatedFundingNewJob(_jobId, _updatedReward);
    }

    function cancelAndWithdraw(uint256 _jobId) external {
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0 && !collectiveJobFunding[_jobId], 
            "cancelAndWithdraw: not a contributor"
        );
        require(
            jobStatus[_jobId] = JobStatus.APPOINTING, 
            "cancelAndWithdraw: already active job"
        );
        jobStatus[_jobId] = JobStatus.CANCELLED;
        withdrawUserContribution(_jobId);

    }

    function voteToCancelFundingNewJob(
        uint256 _jobId
    ) external {
        require(
            collectiveJobFunding[_jobId], 
            "voteToCancelFundingNewJob: must be active job funding"
        );
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0, 
            "voteToCancelFundingNewJob: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.FUNDING && block.timestamp > numberCancelDays * 1 days + fundingDeadline[_jobId] ||
            jobStatus[_jobId] == JobStatus.APPOINTING, 
            "voteToCancelFundingNewJob: cancelling not allowed"
        );
        votesTotalCancel[_jobId] += userContributionToJobReward[_jobId][msg.sender];
        if (votesTotalCancel[_jobId] * 1000 > minCancelQuorum * contributedToJobReward[_jobId]) {
            jobStatus[_jobId] = JobStatus.CANCELLED;
        }
        emit VotedToCancelFundingNewJob(_jobId, msg.sender);
    }

    function voteToChangeJobMaster(
        uint256 _jobId,
        address _proposedMaster
    ) external {
        require(
            collectiveJobFunding[_jobId], 
            "voteToChangeJobMaster: must be active job funding"
        );
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0, 
            "voteToChangeJobMaster: not a contributor"
        );
        require(
            userContributionToJobReward[_jobId][_proposedMaster] > 0, 
            "voteToChangeJobMaster: not a contributor"
        );
        require(
            jobStatus[_jobId] != JobStatus.INACTIVE && 
            jobStatus[_jobId] != JobStatus.CANCELLED, 
            "voteToChangeJobMaster: cancelling not allowed"
        );
        votesTotalMaster[_jobId][_proposedMaster] += userContributionToJobReward[_jobId][msg.sender];
        if (votesTotalMaster[_jobId][_proposedMaster] * 1000 > minMasterQuorum * contributedToJobReward[_jobId]) {
            jobMaster[_jobId] = JobStatus.CANCELLED;
        }
        emit VotedToCancelFundingNewJob(_jobId, msg.sender);
    }

    function withdrawUserContribution(
        uint256 _jobId
    ) public {
        uint256 contribution = userContributionToJobReward[_jobId][msg.sender];
        require(
            contribution > 0, 
            "withdrawUserContribution: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.CANCELLED || jobStatus[_jobId] == JobStatus.SUCCESSFULCHALLENGE, 
            "withdrawUserContribution: job funding still active"
        );
        multiTokenTransferFunction(jobFundingToken[_jobId], address(this), msg.sender, contribution);
        delete userContributionToJobReward[_jobId][msg.sender];
        emit WithdrawnUserContribution(_jobId, msg.sender, contribution);
    }

    function proposeNewJob(
        uint256 _amount,
        uint256 _share,
        uint256 _apppointedGaang,
        address _tokenAddress, 
        address _appointedDev
    ) public payable {
        require(
            _share <= 1000, 
            "proposeNewJob: wrong shared tokens parameter"
        );
        jobId++;
        if (_apppointedGaang != 0 || _appointedDev != address(0)) {
            if (appointedDev[jobId] != address(0)) {
                appointedDev[jobId] = _appointedDev;
            } else {
                appointedGaang[jobId] = _apppointedGaang;
            }
        }
        jobStatus[jobId] = JobStatus.APPOINTING;
        uint256 contribution;
        if (msg.value > 0) {
            require(
                _tokenAddress == address(0), 
                "proposeFundingNewJob: wrong token address parameter"
            );
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            contribution = msg.value;
        } else if (_amount > 0) {
            multiTokenTransferFunction(_tokenAddress, msg.sender, address(this), _amount);
            jobFundingToken[jobId] = _tokenAddress;
            contribution = _amount;
        } else { 
            return;
        }
        jobManager[jobId] = msg.sender;
        contributedToJobReward[jobId] += contribution;
        userContributionToJobReward[jobId][msg.sender] += contribution;
        jobRewardAmount[jobId] = _amount;
        shareTodevOrGaang[jobId] = _share;
        emit ProposedNewJob(jobId, msg.sender, jobStatus[_jobId]);
    }

    function batchProposeNewJob(
        uint256[] _rewardAmount,
        uint256[] _amount,
        uint256[] _share,
        uint256[] _apppointedGaang,
        address[] _tokenAddress, 
        address[] _appointeddev
    ) external payable {
        require(
            _collectiveFunding.length == _rewardAmount.length == _amount.length == _share.length == _apppointedGaang.length == _tokenAddress.length == _appointeddev.length, 
            "batchProposeNewJob: wrong parameters length"
        );
        for (uint i = 0; i < _rewardAmount.length; i++) {
            if (_rewardAmount[i] > 0) {
                proposeFundingNewJob(_rewardAmount[i], _amount[i], _share[i], _tokenAddress[i], _apppointedGaang[i], _appointedDev[i]);
            } else {
                proposeNewJob(_amount[i], _share[i], _apppointedGaang[i], _tokenAddress[i], _appointedDev[i]);
            }
        }
    }   

    function bidOnDevOrGaang(
        uint256 _jobId,
        uint256 _gaangId,
        address _dev,
        uint256 _amount
    ) external payable {
        uint256 contribution;
        if (msg.value > 0 && jobFundingToken[_jobId] == address(0)) {
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            contribution = msg.value;
        } else if (_amount > 0) {
            multiTokenTransferFunction(jobFundingToken[_jobId], msg.sender, address(this), _amount);
            contribution = _transferedWmaticOrGhst;
        } else { 
            return;
        }
        if (_dev != address(0)) {
            bidOnDev[_jobId][msg.sender][_dev] += _amount;
            totalBidOnDev[_jobId][_dev] += _amount;
        } else if (_apppointedGaang != 0) {
            bidOnGaang[_jobId][msg.sender][_gaangId] += _amount;
            totalBidOnGaang[_jobId][_gaangId] += _amount;
        }
        lastBid[_jobId][msg.sender] = block.timestamp;
        emit BidOnDevOrGaang(msg.sender, _gaangId, _dev);
    }

    function withdrawBid(
        uint256 _jobId,
        uint256 _gaangId,
        address _dev,
        uint256 _amount
    ) public {
        require(
            block.timestamp >= lastBid[_jobId][msg.sender] + numberWithdrawBidDays * 1 days || 
            appointedDev[_jobId] != address(0) && bidOnDev[_jobId][msg.sender][appointedDev[_jobId]] > 0 ||
            appointedGaang[_jobId] != 0 && bidOnGaang[_jobId][msg.sender][appointedGaang[_jobId]] > 0, 
            "withdrawBid: cannot withdraw"
        );
        if (appointedDev[_jobId] != address(0)) {
            require(
                bidOnDev[_jobId][msg.sender][_dev] >= _amount, 
                "withdrawBid: amount exceeding total user bid contribution"
            );
            bidOnDev[_jobId][msg.sender][appointedDev[_jobId]] -= _amount;
        } else {
            require(
                bidOnGaang[_jobId][msg.sender][_gaangId] >= _amount, 
                "withdrawBid: amount exceeding total user bid contribution"
            );
            bidOnGaang[_jobId][msg.sender][appointedGaang[_jobId]] -= _amount;
        }
        multiTokenTransferFunction(jobFundingToken[_jobId], address(this), msg.sender, _amount);
        emit WithdrawnBid(_jobId, msg.sender, _gaangId, _dev, _amount);
    }

    function batchWithdrawBid(
        uint256[] _jobId,
        uint256[] _gaangId,
        address[] _dev,
        uint256[] _amount
    ) external {
        require(
            _jobId.length == _gaangId.length == _dev.length == _amount.length, 
            "batchWithdrawBid: wrong parameters length"
        );
        for (uint i = 0; i < _jobId.length; i++) {
            withdrawBid(_jobId[i], _gaangId, _dev[i], _amount[i]);
        }
    }

    function appointDevOrGaang(
        uint256 _jobId,
        uint256 _apppointedGaang,
        address _appointedDev
    ) external {
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0 && !collectiveJobFunding[_jobId], 
            "appointDevOrGaang: not a contributor"
        );
        if (_appointedDev != address(0) && devProposal[_jobId][_appointedDev] > 0) {
            if (devProposal[_jobId][_appointedDev] > contributedToJobReward[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = devProposal[_jobId][_appointedDev];
                fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                contributeFundingNewJob(_jobId, jobFundingToken[_jobId], jobRewardAmount[_jobId]);
            } else if (devProposal[_jobId][_appointedDev] == contributedToJobReward[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                contributedToJobReward[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
            }
            appointedDev[_jobId] = _appointedDev;
        } else if (_apppointedGaang != 0 && gaangProposal[_jobId][_apppointedGaang] > 0) {
            if (gaangProposal[_jobId][_apppointedGaang] > contributedToJobReward[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = gaangProposal[_jobId][_apppointedGaang];
                fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                contributeFundingNewJob(_jobId, jobFundingToken[_jobId], jobRewardAmount[_jobId]);
            } else if (gaangProposal[_jobId][_apppointedGaang] == contributedToJobReward[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                contributedToJobReward[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
            }
            appointedGaang[_jobId] = _apppointedGaang;
        } else {
            return;
        }
        emit AcceptedDevOrGaangProposal(_jobId, msg.sender, jobStatus[_jobId]);
    }
    
    function voteToAppointDevOrGaang(
        uint256 _jobId,
        uint256 _apppointedGaang,
        address _appointedDev
    ) external {
        require(
            collectiveJobFunding[_jobId], 
            "voteToAppointDevOrGaang: must be active job funding"
        );
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0, 
            "voteToAppointDevOrGaang: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING, 
            "voteToAppointDevOrGaang: job funding still active"
        );
        if (_appointedDev != address(0)) {
            votesTotalApproveDev[_jobId][_appointeddev] += userContributionToJobReward[_jobId][msg.sender];
            if (votesTotalApproveDev[_jobId][_appointedDev] * 1000 > minApproveQuorum * contributedToJobReward[_jobId]) {
                if (devProposal[_jobId][_appointedDev] > contributedToJobReward[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                    jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                    jobRewardAmount[_jobId] = devProposal[_jobId][_appointedDev];
                    fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                } else if (devProposal[_jobId][_appointedDev] == contributedToJobReward[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                    contributedToJobReward[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                }
                appointedDev[_jobId] = _appointedDev;
            } 
        } else if (_apppointedGaang != 0) {
            votesTotalApproveGaang[_jobId][_apppointedGaang] += userContributionToJobReward[_jobId][msg.sender];
            if (votesTotalApproveGaang[_jobId][_apppointedGaang] * 1000 > minApproveQuorum * contributedToJobReward[_jobId]) {
                if (gaangProposal[_jobId][_apppointedGaang] > contributedToJobReward[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                    jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                    jobRewardAmount[_jobId] = gaangProposal[_jobId][_apppointedGaang];
                    fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                } else if (gaangProposal[_jobId][_apppointedGaang] == contributedToJobReward[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                    contributedToJobReward[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                }
                appointedGaang[_jobId] = _apppointedGaang;
            } 
        } else {
            return;
        }
        emit VotedToAppointDevOrGaang(_jobId, msg.sender, jobStatus[_jobId]);
    }

    function acceptJobOrCommit(
        uint256 _jobId,
        address _tokenAddress,
        uint256 _gaangNumber,
        uint256 _askedRewardAmount,
        uint256 _goodwillAmount
    ) external payable {
        require(
            isGaangMember[msg.sender][_gaangNumber], 
            "acceptJobOrCommit: not a gaang member"
        );
        require(
            jobFundingToken[_jobId] == _tokenAddress, 
            "acceptJobOrCommit: wrong funding token address"
        );
        uint256 contribution;
        if (msg.value > 0) {
            require(
                jobFundingToken[_jobId] == address(0), 
                "acceptJobOrCommit: wrong funding token address"
            );
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            contribution = msg.value;
        } else if (_amount > 0) {
            multiTokenTransferFunction(jobFundingToken[_jobId], msg.sender, address(this), _goodwillAmount);
            contribution = _goodwillAmount;
        } else { 
            return;
        }
        if (_gaangNumber > 0) {
            require(
                isGaangMember[msg.sender][_gaangNumber], 
                "acceptJobOrCommit: not a gaang member"
            );
            if (_askedRewardAmount == contributedToJobReward[_jobId] + totalBidOnGaang[_jobId][_gaangNumber]) {
                contributedToJobReward[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                jobStatus[_jobId] = JobStatus.WORKING;
            }
        } else {
            if (_askedRewardAmount == contributedToJobReward[_jobId] + totalBidOnDev[_jobId][msg.sender]) {
                contributedToJobReward[_jobId] += totalBidOnDev[_jobId][msg.sender];
                jobStatus[_jobId] = JobStatus.WORKING;
            }
        }
        if (contribution > 0) committedGoodWill[msg.sender][_jobId] += _goodwillAmount;
        emit AcceptedJobOrCommit(_jobId, _askedRewardAmount, _goodwillAmount);
    }

    function stakingFunction(
        address _tokenAddressToStakeFrom,
        uint256 _amount
    ) internal {
        if (_tokenAddressToStakeFrom == address(0)) {
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            AaveInterface(aavePoolContract).supply(
                _wmaticContract,
                _amount,
                address(this),
                0
            );
        } else {
            require(
                _tokenAddressToStakeFrom == wmaticContract ||
                _tokenAddressToStakeFrom == aWmaticContract ||
                _tokenAddressToStakeFrom == ghstContract ||
                _tokenAddressToStakeFrom == aGhstContract ||
                _tokenAddressToStakeFrom == wapghstContract,
                "stakingFunction: unauthorized collateral token"
            )
            ERC20lib.transferFrom(_tokenAddressToStakeFrom, msg.sender, address(this), _amount);
            if (_tokenAddressToStakeFrom == ghstContract) {
                uint256 shares = WrappedGhstInterface(wapghstContract).enterWithUnderlying(_amount);
                FarmFacetInterface(farmFacetContract).deposit(0, shares);
            } else if (_tokenAddressToStakeFrom == aGhstContract) {
                uint256 shares = WrappedGhstInterface(wapghstContract).previewDeposit(_amount);
                WrappedGhstInterface(wapghstContract).enter(_amount);
                FarmFacetInterface(farmFacetContract).deposit(0, shares);
            } else if (_tokenAddressToStakeFrom == wapghstContract) {
                FarmFacetInterface(farmFacetContract).deposit(0, _amount);
            } else if (_tokenAddressToStakeFrom == wmaticContract) {
                AaveInterface(aavePoolContract).supply(
                    _wmaticContract,
                    _amount,
                    address(this),
                    0
                );
            }
        } 
    }

    function unstakingFunction(
        address _tokenAddressToUnstakeTo,
        uint256 _amount
    ) internal {
        if (_tokenAddressToStake == address(0)) {
            AaveInterface(aavePoolContract).withdraw(
                wmaticContract,
                _amount,
                address(this)
            );
            WrappedMaticInterface(wrappedMaticContract).withdraw(_amount);
            (bool success, ) = msg.sender.call{value: _amount}("");
        } else {
            require(
                _tokenAddressToStakeTo == wmaticContract ||
                _tokenAddressToStakeTo == aWmaticContract ||
                _tokenAddressToStakeTo == ghstContract ||
                _tokenAddressToStakeTo == aGhstContract ||
                _tokenAddressToStakeTo == wapghstContract,
                "stakingFunction: unauthorized collateral token"
            )
            if (_tokenAddressToStakeTo == ghstContract) {
                uint256 shares = WrappedGhstInterface(wapghstContract).previewRedeem(_amount);
                FarmFacetInterface(farmFacetContract).withdraw(0, shares);
                WrappedGhstInterface(wapghstContract).leaveToUnderlying(shares);
                AaveInterface(aavePoolContract).withdraw(
                    ghstContract,
                    _amount,
                    address(this)
                );
            } else if (_tokenAddressToStakeTo == aGhstContract) {
                uint256 shares = WrappedGhstInterface(wapghstContract).previewRedeem(_amount);
                FarmFacetInterface(farmFacetContract).withdraw(0, shares);
                WrappedGhstInterface(wapghstContract).leave(shares);
            } else if (_tokenAddressToStakeTo == wapghstContract) {
                FarmFacetInterface(farmFacetContract).withdraw(0, _amount);
            } else if (_tokenAddressToStakeTo == wmaticContract) {
                AaveInterface(aavePoolContract).withdraw(
                    wmaticContract,
                    _amount,
                    address(this)
                );
            }
            ERC20lib.transferFrom(_tokenAddressToStakeTo, address(this), msg.sender, _amount);
        } 
    }

    function updateUserContributionBalance(
        uint256 _jobId,
        address _user
    ) internal {
        if (!userUpdatedBalance[_user]) {
            if (appointedDev[_jobId] != address(0) && bidOnDev[_jobId][_user][appointedDev[_jobId]] > 0) {
            userContributionToJobReward[_jobId][_user] += bidOnDev[_jobId][_user][appointedDev[_jobId]];
            } else if (appointedGaang[_jobId] != 0 && bidOnGaang[_jobId][_user][appointedGaang[_jobId]] > 0) {
                userContributionToJobReward[_jobId][_user] += bidOnGaang[_jobId][_user][appointedGaang[_jobId]];
            }
            userUpdatedBalance[_user] = true;
        }
    }
}
    
WrappedMaticInterface(wrappedMaticContract).deposit{value: _value}();
WrappedMaticInterface(wrappedMaticContract).transfer(_to, _value);