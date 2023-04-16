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
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
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
            "contributeFundingNewJob: funding deadline expired"
        );
        uint256 contribution;
        if (msg.value > 0 && jobFundingToken[_jobId] == address(0)) {
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            contribution = msg.value;
        } else if (_amount > 0 && _tokenAddress == jobFundingToken[_jobId]) {
            multiTokenTransferFunction(_tokenAddress, msg.sender, address(this), _amount);
            contribution = _transferedWmaticOrGhst;
        } else { 
            return;
        }
        contributedToJobReward[_jobId] += contribution;
        userContributionToJobReward[_jobId][msg.sender] += contribution;
        if (contributedToJobReward[_jobId] >= jobRewardAmount[_jobId]) jobStatus[_jobId] = JobStatus.WORKING;
        emit ContributedFundingNewJob(_jobId, contribution);
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
    ) external {
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
    ) external {
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

    function acceptDevOrGaangProposal(
        uint256 _jobId,
        uint256 _apppointedGaang,
        address _appointedDev
    ) external {
        if (_appointedDev != address(0) && devProposal[_jobId][_appointedDev] > 0) {
            if (devProposal[_jobId][_appointedDev] > contributedToJobReward[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = devProposal[_jobId][_appointedDev];
                fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
            } else {
                appointedDev[_jobId] = _appointedDev;
                contributedToJobReward[_jobId] += totalBidOnDev[_jobId][_appointedDev];
            }
        } else if (_apppointedGaang != 0 && gaangProposal[_jobId][_apppointedGaang] > 0) {
            if (gaangProposal[_jobId][_apppointedGaang] > contributedToJobReward[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = gaangProposal[_jobId][_apppointedGaang];
                fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
            } else {
                appointedGaang[_jobId] = _apppointedGaang;
                contributedToJobReward[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
            }
        } else {
            return;
        }
        emit AcceptedDevOrGaangProposal(_jobId, msg.sender, jobStatus[_jobId]);
    }
    
    function voteToAppointDevOrGaangOrAcceptProposal(
        uint256 _jobId,
        uint256 _apppointedGaang,
        address _appointedDev
    ) external {
        require(
            collectiveJobFunding[_jobId], 
            "voteToAppointDevOrGaangOrAcceptProposal: must be active job funding"
        );
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0, 
            "voteToAppointDevOrGaangOrAcceptProposal: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING || jobStatus[_jobId] == JobStatus.EXTRAFUNDING, 
            "voteToAppointDevOrGaangOrAcceptProposal: job funding still active"
        );
        if (_appointedDev != address(0)) {
            votesTotalApprovedev[_jobId][_appointeddev] += userContributionToJobReward[_jobId][msg.sender];
            if (votesTotalApprovedev[_jobId][_appointedDev] * 1000 > minApproveQuorum * contributedToJobReward[_jobId]) {
                if (devProposal[_jobId][_appointedDev] > contributedToJobReward[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                    jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                    jobRewardAmount[_jobId] = devProposal[_jobId][_appointedDev];
                    fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                } else {
                    appointeddev[_jobId] = _appointedDev;
                    contributedToJobReward[_jobId] += totalBidOnDev[_jobId][_appointedDev];
                    jobStatus[_jobId] = JobStatus.WORKING;
                }
            } 
        } else if (_apppointedGaang != 0) {
            votesTotalApproveGaang[_jobId][_apppointedGaang] += userContributionToJobReward[_jobId][msg.sender];
            if (votesTotalApproveGaang[_jobId][_apppointedGaang] * 1000 > minApproveQuorum * contributedToJobReward[_jobId]) {
                if (gaangProposal[_jobId][_apppointedGaang] > contributedToJobReward[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                    jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                    jobRewardAmount[_jobId] = gaangProposal[_jobId][_apppointedGaang];
                    fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                } else {
                    appointedGaang[_jobId] = _apppointedGaang;
                    contributedToJobReward[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                    jobStatus[_jobId] = JobStatus.WORKING;
                }
            } 
        } else {
            return;
        }
        emit VotedToApproveAppointedDevOrGaang(_jobId, msg.sender, jobStatus[_jobId]);
    }

    function acceptJobProposal(
        uint256 _jobId,
        uint256 _rewardAmount,
        uint256 _goodwillAmount
    ) external {
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
        if (_rewardAmount <= contributedToJobReward[_jobId] + totalBidOnDev[_jobId][_appointedDev]) jobStatus[_jobId] = JobStatus.WORKING;
    }

    function multiTokenTransferFunction(
        address _tokenAddress,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_tokenAddress == address(0)) {
            (bool success, ) = _to.call{value: _value, gas: maticGas}("");
            if (!success) {
                WrappedMaticInterface(wrappedMaticContract).deposit{value: _amount}();
                WrappedMaticInterface(wrappedMaticContract).transfer(_to, _amount);
            }
        } else {
            require(
                _tokenAddress == wmaticContract ||
                _tokenAddress == awmaticContract ||
                _tokenAddress == ghstContract ||
                _tokenAddress == aghstContract ||
                _tokenAddress == wapghstContract,
                "multiTokenTransferFunction: unauthorized collateral token"
            )
            ERC20lib.transferFrom(_tokenAddress, _from, _to, _amount);
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