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
        uint256 _addToBlock,
        uint256 _rewardAmount,
        uint256 _amount,
        uint256 _tokenAddress,
        uint256 _apppointedGaang,
        address _appointedDev
    ) public payable {
        require(
            jobStatus[_jobId] == JobStatus.INACTIVE, 
            "proposeFundingNewJob: already active funding"
        );
        jobId++;
        uint256 contribution;
        if (msg.value > 0) {
            require(
                _tokenAddress == address(0), 
                "proposeFundingNewJob: wrong token address parameter"
            );
            stakingFunction();
            contribution = msg.value;
        } else if (_amount > 0) {
            stakingFunction(_tokenAddress, _amount);
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
        if (_addToBlock != 0) {
            if (msg.sender == rootBlockOwner[_addToBlock]) {
                devBlock[jobId] = _addToBlock;
            } else {
                requestedAddBlock[_addToBlock][jobId] = true;
            }
        }
        _mint(msg.sender, jobId, 1000 * contribution, "");
        collectiveJobFunding[jobId] = true;
        fundingDeadline[jobId] = block.timestamp + numberFundingDays * 1 days;
        jobMaster[jobId] = msg.sender;
        jobTreasury[jobId] += contribution;
        userContributionToJobTreasury[jobId][msg.sender] += contribution;
        jobRewardAmount[jobId] = _rewardAmount;
        emit ProposedFundingNewJob(jobId, _rewardAmount, contribution);
    }

    function contributeFundingNewJob(
        uint256 _jobId,
        uint256 _amount
    ) public payable {
        require(
            jobStatus[_jobId] == JobStatus.EXTRAFUNDING ||
            jobStatus[_jobId] == JobStatus.FUNDING, 
            "contributeFundingNewJob: no ongoing funding"
        );
        if (jobStatus[_jobId] == JobStatus.EXTRAFUNDING) {
            updateUserContributionBalance(_jobId, msg.sender);
            if (collectiveJobFunding[_jobId]) {
                require(
                    block.timestamp <= fundingDeadline[_jobId], 
                    "contributeFundingNewJob: funding deadline expired"
                );
            }
        }
        uint256 contribution;
        if (msg.value > 0) {
            require(
                jobFundingToken[_jobId] == address(0), 
                "contributeFundingNewJob: wrong funding token address"
            );
            stakingFunction();
            contribution = msg.value;
        } else if (_amount > 0) {
            stakingFunction(jobFundingToken[_jobId], _amount);
            contribution = _amount;
        } else { 
            return;
        }
        if (collectiveJobFunding[_jobId]) {
            _mint(msg.sender, _jobId, 1000 * contribution, "");
        }
        jobTreasury[_jobId] += contribution;
        userContributionToJobTreasury[_jobId][msg.sender] += contribution;
        if (jobTreasury[_jobId] >= jobRewardAmount[_jobId]) {
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
            jobMaster[_jobId] == msg.sender, 
            "updateFundingNewJob: must be the job initiator"
        );
        require(
            _updatedReward >= jobTreasury[_jobId], 
            "updateFundingNewJob: must be greater than already collected funds for the job reward"
        );
        jobRewardAmount[_jobId] = _updatedReward;
        emit UpdatedFundingNewJob(_jobId, _updatedReward);
    }

    function cancelAndWithdraw(uint256 _jobId) external {
        require(
            jobMaster[_jobId] == msg.sender && !collectiveJobFunding[_jobId], 
            "cancelAndWithdraw: not a contributor"
        );
        require(
            jobStatus[_jobId] = JobStatus.APPOINTING ||
            jobStatus[_jobId] == JobStatus.WORKING, 
            "cancelAndWithdraw: already active job"
        );
        jobStatus[_jobId] = JobStatus.CANCELLED;
        withdrawUserContribution(_jobId);
    }

    function voteToCancelFundingNewJob(
        uint256 _jobId
    ) external {
        require(
            balanceOf(msg.sender, _jobId) > 0, 
            "voteToCancelFundingNewJob: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.FUNDING && block.timestamp > numberCancelDays * 1 days + fundingDeadline[_jobId] ||
            jobStatus[_jobId] == JobStatus.APPOINTING ||
            jobStatus[_jobId] == JobStatus.WORKING, 
            "voteToCancelFundingNewJob: cancelling not allowed"
        );
        votesTotalCancel[_jobId] += balanceOf(msg.sender, _jobId);
        if (votesTotalCancel[_jobId] * 1000 > minCancelQuorum * totalSupply[_jobId]) {
            jobStatus[_jobId] = JobStatus.CANCELLED;
            delete votesTotalCancel[_jobId];
        }
        emit VotedToCancelFundingNewJob(_jobId, msg.sender);
    }

    function voteToChangeJobMaster(
        uint256 _jobId,
        address _proposedMaster
    ) external {
        require(
            balanceOf(msg.sender, _jobId) > 0, 
            "voteToChangeJobMaster: not a contributor"
        );
        require(
            balanceOf(_proposedMaster, _jobId) > 0, 
            "voteToChangeJobMaster: proposed job master not a contributor"
        );
        require(
            jobStatus[_jobId] != JobStatus.INACTIVE && 
            jobStatus[_jobId] != JobStatus.CANCELLED, 
            "voteToChangeJobMaster: cancelling not allowed"
        );
        votesTotalMaster[_jobId][_proposedMaster] += balanceOf(msg.sender, _jobId);
        if (votesTotalMaster[_jobId][_proposedMaster] * 1000 > minMasterQuorum * totalSupply(_jobId)) {
            jobMaster[_jobId] = _proposedMaster;
            delete votesTotalMaster[_jobId][_proposedMaster];
        }
        emit VotedToCancelFundingNewJob(_jobId, msg.sender, _proposedMaster);
    }

    function withdrawUserContribution(
        uint256 _jobId
    ) public {
        require(
            jobStatus[_jobId] == JobStatus.CANCELLED || jobStatus[_jobId] == JobStatus.SETTLEDCHALLENGE, 
            "withdrawUserContribution: job funding still active"
        );
        uint256 contribution;
        if (collectiveJobFunding[_jobId]) {
            require(
                balanceOf(msg.sender, _jobId) > 0 && !claimed[_jobId][msg.sender], 
                "withdrawUserContribution: not a contributor"
            );
            updateUserTokenShare(_jobId, msg.sender);
            if (jobStatus[_jobId] == JobStatus.SETTLEDCHALLENGE) {
                contribution = (contribution / totalSupply(_jobId)) * (arbitrageForEmployer[_jobId] / 1000) * jobTreasury[_jobId];
            } else {
                contribution = (contribution / totalSupply(_jobId)) * jobTreasury[_jobId];
            }
        } else {
            require(
                jobMaster[_jobId] == msg.sender, 
                "withdrawUserContribution: not a contributor"
            );
            contribution = jobTreasury[_jobId];
        }
        unstakingFunction(jobFundingToken[_jobId], msg.sender, contribution);
        claimed[_jobId][msg.sender] = true;
        emit WithdrawnUserContribution(_jobId, msg.sender, contribution);
    }

    function proposeNewJob(
        uint256 _chain,
        uint256 _addToBlock,
        uint256 _amount,
        uint256 _apppointedGaang,
        address _tokenAddress, 
        address _appointedDev
    ) public payable {
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
            stakingFunction();
            contribution = msg.value;
        } else if (_amount > 0) {
            stakingFunction(_tokenAddress, _amount);
            jobFundingToken[jobId] = _tokenAddress;
            contribution = _amount;
        } else { 
            return;
        }
        if (_addToBlock != address(0)) {
            if (msg.sender == rootBlockOwner[_addToBlock]) {
                devBlock[jobId] = _addToBlock;
            } else {
                requestedAddBlock[_addToBlock][jobId] = true;
            }
        } else {
            devBlock[jobId] = blockId++;
            if (_chain != 0) {
                chainNumber[blockId] = _chain;
            } else {
                chainNumber[blockId] = chainId++;
            }
        }
        _mint(msg.sender, jobId, 1000 * contribution, "");
        jobMaster[jobId] = msg.sender;
        jobTreasury[jobId] += contribution;
        userContributionToJobTreasury[jobId][msg.sender] += contribution;
        jobRewardAmount[jobId] = _amount;
        emit ProposedNewJob(jobId, msg.sender, jobStatus[_jobId]);
    }

    function batchProposeNewJob(
        uint256[] _addToBlock,
        uint256[] _rewardAmount,
        uint256[] _amount,
        uint256[] _apppointedGaang,
        address[] _tokenAddress, 
        address[] _appointedDev,
        bool[] _hereditary
    ) external payable {
        require(
            _addToBlock.length == _rewardAmount.length == _amount.length == _apppointedGaang.length == _tokenAddress.length == _appointedDev.length == _hereditary.length, 
            "batchProposeNewJob: wrong parameters length"
        );
        for (uint i = 0; i < _rewardAmount.length; i++) {
            if (_rewardAmount[i] > 0) {
                proposeFundingNewJob(_addToBlock[i], _rewardAmount[i], _amount[i], _tokenAddress[i], _apppointedGaang[i], _appointedDev[i]);
            } else {
                proposeNewJob(_addToBlock[i], _amount[i], _apppointedGaang[i], _tokenAddress[i], _appointedDev[i], _hereditary[i]);
            }
        }
    }   

    function bidOnDevOrGaang(
        uint256 _jobId,
        uint256 _gaangId,
        address _dev,
        uint256 _amount
    ) external payable {
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING,
            "bidOnDevOrGaang: cannot bid"
        );
        require(
            jobMaster[_jobId] == msg.sender && !collectiveJobFunding[_jobId] ||
            balanceOf(msg.sender, _jobId) > 0, 
            "bidOnDevOrGaang: not a contributor or job owner"
        );
        uint256 contribution;
        if (msg.value > 0 && jobFundingToken[_jobId] == address(0)) {
            stakingFunction();
            contribution = msg.value;
        } else if (_amount > 0) {
            stakingFunction(jobFundingToken[_jobId], _amount);
            contribution = _amount;
        } else { 
            return;
        }
        if (_dev != address(0)) {
            bidOnDev[_jobId][msg.sender][_dev] += _amount;
            totalBidOnDev[_jobId][_dev] += _amount;
            lastBidOnDev[_jobId][msg.sender][_dev] = block.timestamp;
        } else if (_apppointedGaang != 0) {
            bidOnGaang[_jobId][msg.sender][_gaangId] += _amount;
            totalBidOnGaang[_jobId][_gaangId] += _amount;
            lastBidOnGaang[_jobId][msg.sender][_gaangId] = block.timestamp;
        }
        emit BidOnDevOrGaang(msg.sender, _gaangId, _dev);
    }

    function withdrawBid(
        uint256 _jobId,
        uint256 _gaangId,
        address _dev,
        uint256 _amount
    ) public {
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING || 
            appointedDev[_jobId] != address(0) && appointedDev[_jobId] != _dev ||
            appointedGaang[_jobId] != 0 && appointedGaang[_jobId] != _gaangId,
            "withdrawBid: cannot withdraw bid on this dev or gaang"
        );
        if (appointedDev[_jobId] != address(0)) {
            require(
                block.timestamp >= lastBidOnDev[_jobId][msg.sender][_dev] + numberWithdrawBidDays * 1 days,
                "withdrawBid: cannot withdraw before cooling time is ended"
            );
            require(
                bidOnDev[_jobId][msg.sender][_dev] >= _amount, 
                "withdrawBid: amount exceeding total user bid contribution"
            );
            bidOnDev[_jobId][msg.sender][_dev] -= _amount;
        } else {
            require(
                block.timestamp >= lastBidOnGaang[_jobId][msg.sender][_gaangId] + numberWithdrawBidDays * 1 days,
                "withdrawBid: cannot withdraw before cooling time is ended"
            );
            require(
                bidOnGaang[_jobId][msg.sender][_gaangId] >= _amount, 
                "withdrawBid: amount exceeding total user bid contribution"
            );
            bidOnGaang[_jobId][msg.sender][_gaangId] -= _amount;
        }
        unstakingFunction(jobFundingToken[_jobId], msg.sender, _amount);
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
            withdrawBid(_jobId[i], _gaangId[i], _dev[i], _amount[i]);
        }
    }

    function appointDevOrGaang(
        uint256 _jobId,
        uint256 _apppointedGaang,
        address _appointedDev
    ) external payable {
        require(
            jobMaster[_jobId] == msg.sender && !collectiveJobFunding[_jobId], 
            "appointDevOrGaang: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING || 
            jobStatus[_jobId] == JobStatus.WORKING, 
            "appointDevOrGaang: job funding still active"
        );
        if (_appointedDev != address(0)) {
            if (devProposal[_jobId][_appointedDev] > jobTreasury[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = devProposal[_jobId][_appointedDev];
                contributeFundingNewJob(_jobId, jobRewardAmount[_jobId]);
            } else if (devProposal[_jobId][_appointedDev] == jobTreasury[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                jobTreasury[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                jobStatus[_jobId] = JobStatus.WORKING;
            } else {
                jobStatus[_jobId] = JobStatus.APPOINTING;
            }
            appointedDev[_jobId] = _appointedDev;
        } else if (_apppointedGaang != 0) {
            if (gaangProposal[_jobId][_apppointedGaang] > jobTreasury[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = gaangProposal[_jobId][_apppointedGaang];
                contributeFundingNewJob(_jobId, jobRewardAmount[_jobId]);
            } else if (gaangProposal[_jobId][_apppointedGaang] == jobTreasury[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                jobTreasury[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                jobStatus[_jobId] = JobStatus.WORKING;
            } else {
                jobStatus[_jobId] = JobStatus.APPOINTING;
            }
            appointedGaang[_jobId] = _apppointedGaang;
        }
        emit AcceptedDevOrGaangProposal(_jobId, msg.sender, jobStatus[_jobId]);
    }
    
    function voteToAppointDevOrGaang(
        uint256 _jobId,
        uint256 _apppointedGaang,
        address _appointedDev
    ) external {
        require(
            balanceOf(msg.sender, _jobId) > 0, 
            "voteToAppointDevOrGaang: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING || 
            jobStatus[_jobId] == JobStatus.WORKING, 
            "voteToAppointDevOrGaang: job funding still active"
        );
        if (_appointedDev != address(0)) {
            votesTotalApproveDev[_jobId][_appointeddev] += balanceOf(msg.sender, _jobId);
            if (votesTotalApproveDev[_jobId][_appointedDev] * 1000 > minApproveQuorum * totalSupply[_jobId]) {
                if (devProposal[_jobId][_appointedDev] > jobTreasury[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                    jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                    jobRewardAmount[_jobId] = devProposal[_jobId][_appointedDev];
                    fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                } else if (devProposal[_jobId][_appointedDev] == jobTreasury[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                    jobTreasury[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                    jobStatus[_jobId] = JobStatus.WORKING;
                } else {
                    jobStatus[_jobId] = JobStatus.APPOINTING;
                }
                appointedDev[_jobId] = _appointedDev;
                delete votesTotalApproveDev[_jobId][_appointedDev];
            } 
        } else if (_apppointedGaang != 0) {
            votesTotalApproveGaang[_jobId][_apppointedGaang] += balanceOf(msg.sender, _jobId);
            if (votesTotalApproveGaang[_jobId][_apppointedGaang] * 1000 > minApproveQuorum * totalSupply[_jobId]) {
                if (gaangProposal[_jobId][_apppointedGaang] > jobTreasury[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                    jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                    jobRewardAmount[_jobId] = gaangProposal[_jobId][_apppointedGaang];
                    fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
                } else if (gaangProposal[_jobId][_apppointedGaang] == jobTreasury[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                    jobTreasury[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                    jobStatus[_jobId] = JobStatus.WORKING;
                } else {
                    jobStatus[_jobId] = JobStatus.APPOINTING;
                }
                appointedGaang[_jobId] = _apppointedGaang;
                delete votesTotalApproveGaang[_jobId][_apppointedGaang];
            } 
        } else {
            return;
        }
        emit VotedToAppointDevOrGaang(_jobId, msg.sender, jobStatus[_jobId]);
    }

    function acceptJobOrCommit(
        uint256 _jobId,
        uint256 _gaangNumber,
        uint256 _askedRewardAmount,
        uint256 _goodwillAmount
    ) external payable {
        require(
            isGaangMember[msg.sender][_gaangNumber], 
            "acceptJobOrCommit: not a gaang member"
        );
        uint256 contribution;
        if (msg.value > 0) {
            require(
                jobFundingToken[_jobId] == address(0), 
                "acceptJobOrCommit: wrong funding token address"
            );
            stakingFunction();
            contribution = msg.value;
        } else if (_goodwillAmount > 0) {
            stakingFunction(jobFundingToken[_jobId], _goodwillAmount);
            contribution = _goodwillAmount;
        } else { 
            return;
        }
        if (_gaangNumber > 0) {
            require(
                isGaangMember[msg.sender][_gaangNumber], 
                "acceptJobOrCommit: not a gaang member"
            );
            if (_askedRewardAmount == jobTreasury[_jobId] + totalBidOnGaang[_jobId][_gaangNumber]) {
                jobTreasury[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
                jobStatus[_jobId] = JobStatus.WORKING;
            }
            if (contribution > 0) committedGoodwillFromGaang[_gaangNumber][_jobId] += _goodwillAmount;
        } else {
            if (_askedRewardAmount == jobTreasury[_jobId] + totalBidOnDev[_jobId][msg.sender]) {
                jobTreasury[_jobId] += totalBidOnDev[_jobId][msg.sender];
                jobStatus[_jobId] = JobStatus.WORKING;
            }
        }
        if (contribution > 0) committedGoodwill[msg.sender][_jobId] += _goodwillAmount;
        lastCommitOnJob[msg.sender][_jobId] = block.timestamp;
        emit AcceptedJobOrCommit(_jobId, _askedRewardAmount, _goodwillAmount);
    }

    function withdrawGoodwill(
        uint256 _jobId,
        uint256 _gaangNumber,
        uint256 _decreasedAmount
    ) external {
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING, 
            "withdrawGoodwill: job funding still active"
        );
        require(
            _decreasedAmount >= committedGoodwill[msg.sender][_jobId], 
            "withdrawGoodwill: decreased amount too high"
        );
        require(
            block.timestamp >= lastCommitOnJob[msg.sender][_jobId] + numberWithdrawCommitDays * 1 days,
            "withdrawGoodwill: cannot withdraw before cooling time is ended"
        );
        if (_gaangNumber > 0) {
            require(
                isGaangMember[msg.sender][_gaangNumber], 
                "withdrawGoodwill: not a gaang member"
            );
            committedGoodwillFromGaang[_gaangNumber][_jobId] -= _decreasedAmount;
        }
        committedGoodwill[msg.sender][_jobId] -= _decreasedAmount;
        unstakingFunction(jobFundingToken[_jobId], msg.sender, _amount);
        emit WithdrawnGoodwill(_jobId, _decreasedAmount);
    }

    function batchWithdrawGoodwill(
        uint256[] _jobId,
        uint256[] _gaangNumber,
        address[] _decreasedAmount
    ) external {
        require(
            _jobId.length == _gaangNumber.length == _decreasedAmount.length, 
            "batchWithdrawGoodwill: wrong parameters length"
        );
        for (uint i = 0; i < _jobId.length; i++) {
            withdrawGoodwill(_jobId[i], _gaangNumber[i], _decreasedAmount[i]);
        }
    }

    function payWorker(
        uint256 _jobId,
        uint256 _amount
    ) external payable {
        require(
            jobStatus[_jobId] == JobStatus.WORKING, 
            "payWorker: no work ongoing"
        );
        require(
            jobMaster[_jobId] == msg.sender && !collectiveJobFunding[_jobId], 
            "payWorker: not a contributor"
        );
        if (_amount >= jobTreasury[_jobId]) {
            jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
            jobRewardAmount[_jobId] = _amount;
            contributeFundingNewJob(_jobId, jobFundingToken[_jobId], jobRewardAmount[_jobId]);
        }
        workerPaymentFunction(_jobId, _amount);
        emit PaidWorker(_jobId, jobFundingToken[_jobId], _amount);
    }

    function voteToPayWorker(
        uint256 _jobId,
        uint256 _amount
    ) external {
        require(
            balanceOf(msg.sender, _jobId) > 0, 
            "voteToPayWorker: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.WORKING, 
            "voteToPayWorker: not an active job"
        );
        updateUserTokenShare(_jobId, msg.sender);
        votesTotalPayWorker[_jobId][_amount] += balanceOf(msg.sender, _jobId);
        if (votesTotalPayWorker[_jobId][_amount] * 1000 > minPayQuorum * totalSupply[_jobId]) {
            if (_amount >= jobTreasury[_jobId]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = _amount;
                fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
            } else {
                workerPaymentFunction(_jobId, _amount);
            }
            delete votesTotalPayWorker[_jobId][_amount];
        }
        emit VotedToPayWorker(_jobId, jobStatus[_jobId], jobFundingToken[_jobId], _amount);
    }

    function requestPayment(
        uint256 _jobId,
        uint256 _amount,
        uint256 _gaangNumber
    ) external {
        require(
            jobStatus[_jobId] == JobStatus.WORKING ||
            jobStatus[_jobId] == JobStatus.SETTLEDCHALLENGE, 
            "requestPayment: job funding still active"
        );
        if (_gaangNumber > 0) {
            require(
                isGaangMember[msg.sender][_gaangNumber], 
                "requestPayment: not an appointed gaang member"
            );
        } else {
            require(
                msg.sender == appointedDev[_jobId], 
                "requestPayment: not the appointed dev"
            );
        }
        if (jobStatus[_jobId] == JobStatus.SETTLEDCHALLENGE) {
            workerPaymentFunction(_jobId, (1000 - arbitrageForEmployer[_jobId]) / 1000 * jobTreasury[_jobId]);
        } else if (lastRequestForPayment[_jobId] == 0) {
            require(
                _amount >= jobTreasury[_jobId], 
                "requestPayment: not enough treasury funds"
            );
            lastRequestForPayment[_jobId] = block.timestamp;
            amountToPay[_jobId] = _amount;
        } else if (block.timestamp >= lastRequestForPayment[_jobId] + numberWithdrawPaymentDays * 1 days) {
            if (amountToPay[_jobId] > jobTreasury[_jobId]) amountToPay[_jobId] = jobTreasury[_jobId];
            workerPaymentFunction(_jobId, amountToPay[_jobId]);
        } else {
            return;
        }
        emit RequestedPayment(_jobId, _amount);
    }

    function challenge(
        uint256 _jobId,
        uint256 _gaangNumber
    ) external {
        require(
            jobStatus[_jobId] == JobStatus.WORKING ||
            jobStatus[_jobId] == JobStatus.APPOINTING, 
            "challenge: job funding still active"
        );
        if (_gaangNumber > 0) {
            require(
                isGaangMember[msg.sender][_gaangNumber], 
                "challenge: not an appointed gaang member"
            );
        } else {
            require(
                msg.sender == appointedDev[_jobId], 
                "challenge: not the appointed dev"
            );
        } else {
            require(
                !collectiveJobFunding[_jobId] && jobMaster[_jobId] == msg.sender ||
                collectiveJobFunding[_jobId] && msg.sender == jobMaster[_jobId], 
                "challenge: must be a job Master"
            );
        }
        jobStatus[_jobId] = JobStatus.CHALLENGED;
        emit Challenged(_jobId, jobStatus[_jobId]);
    }

    function voteToChallenge(
        uint256 _jobId
    ) external {
        require(
            collectiveJobFunding[_jobId], 
            "voteToChallenge: must be active job funding"
        );
        require(
            balanceOf(msg.sender, _jobId) > 0, 
            "voteToChallenge: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.WORKING ||
            jobStatus[_jobId] == JobStatus.APPOINTING, 
            "voteToChallenge: not an active job"
        );
        updateUserTokenShare(_jobId, msg.sender);
        votesTotalChallenge[_jobId][_amount] += balanceOf(msg.sender, _jobId);
        if (votesTotalChallenge[_jobId][_amount] * 1000 > minChallengeQuorum * totalSupply[_jobId]) {
            jobStatus[_jobId] = JobStatus.CHALLENGED;
            delete votesTotalPayWorker[_jobId][_amount];
        }
        emit VotedToChallenge(_jobId, jobStatus[_jobId]);
    }

    function settleChallenge(
        uint256 _jobId,
        uint256 _arbitrageDecision
    ) external {
        require(
            msg.sender == protocolOwner, 
            "settleChallenge: must be active job funding"
        );
        require(
            jobStatus[_jobId] == JobStatus.CHALLENGED, 
            "settleChallenge: job funding still active"
        );
        arbitrageForEmployer[_jobId] = _arbitrageDecision;
        jobStatus[_jobId] = JobStatus.SETTLEDCHALLENGE;
        emit SettledChallenge(_jobId, _arbitrageDecision);
    }

    function createGaang() external {
        gaangId++;
        gaangMember[gaangId][msg.sender] = true;
        gaangHeadCount++;
        emit CreatedGaang(gaangId);
    }

    function voteGaangPayment(
        uint256 _gaangId,
        uint256 _amountToPay,
        address _tokenAddress,
        address[] _paymentReceivers,
        uint256[] _paymentPercentage
    ) external {
        require(
            _amountToPay > gaangTreasury[_gaangId][_tokenAddress], 
            "voteGaangPayment: must be higher than current gaang treasury"
        );
        require(
            gaangMember[_gaangId][msg.sender], 
            "voteGaangPayment: not a gaang member"
        );
        bytes32 memory hashVote = 
            keccak256(
                abi.encodePacked(
                    _amountToPay,
                    _tokenAddress,
                    _paymentReceivers, 
                    _paymentPercentage
                )
            )
        votesTotalGaangPayment[_gaangId][hashVote]++;
        if (votesTotalGaangPayment[_gaangId][hashVote] * 1000 > minGaangPaymentQuorum * gaangHeadCount) {
            uint256 total;
            for (uint i = 0; i < _paymentReceivers.length; i++) {
                total += _paymentPercentage[i];
            }
            require(
                total == 1000, 
                "voteGaangPayment: payment percentage total not equal to 100%"
            );
            for (uint i = 0; i < _paymentReceivers.length; i++) {
                unstakingFunction(_tokenAddress, _paymentReceivers[i], _paymentPercentage * _amountToPay);
            }
            delete votesTotalGaangPayment[_gaangId][hashVote];
        }
        emit VotedGaangPayment(_gaangId, _amountToPay, _tokenAddress);
    }

    function voteGaangAddMember(
        uint256 _gaangId,
        address _newMember
    ) external {
        require(
            gaangMember[_gaangId][msg.sender], 
            "voteGaangAddMember: not a gaang member"
        );
        require(
            !gaangMember[_gaangId][_newMember], 
            "voteGaangAddMember: already a gaang member"
        );
        votesTotalGaangAddMember[_gaangId][_newMember]++;
        if (votesTotalGaangAddMember[_gaangId][_newMember] * 1000 > minGaangAddMemberQuorum * gaangHeadCount) {
            gaangMember[_gaangId][_newMember] = true;
            gaangHeadCount++;
            delete votesTotalGaangAddMember[_gaangId][_newMember];
        }
        emit VotedGaangAddMember(_gaangId, _newMember);
    }

    function voteGaangRemoveMember(
        uint256 _gaangId,
        address _removedMember
    ) external {
        require(
            gaangMember[_gaangId][msg.sender], 
            "voteGaangRemoveMember: not a gaang member"
        );
        require(
            gaangMember[_gaangId][_removedMember], 
            "voteGaangRemoveMember: removed address not a gaang member"
        );
        votesTotalGaangRemoveMember[_gaangId][_removedMember]++;
        if (votesTotalGaangRemoveMember[_gaangId][_removedMember] * 1000 > minGaangRemoveMemberQuorum * gaangHeadCount) {
            delete gaangMember[_gaangId][_removedMember];
            gaangHeadCount--;
            delete votesTotalGaangRemoveMember[_gaangId][_removedMember];
        }
        emit VotedGaangRemoveMember(_gaangId, _removedMember);
    }

    function acceptJobPushRequestOrPullRequest(
        uint256 _blockId,
        uint256 _jobId
    ) external {
          require(
            jobStatus[_jobId] != JobStatus.INACTIVE, 
            "acceptJobPushRequestOrPullRequest: not an active job"
        );
        require(
            msg.sender == rootBlockOwner[_blockId] && updatedBlock[_blockId], 
            "acceptJobPushRequestOrPullRequest: not the root block owner"
        );
        if (jobPushRequest[_blockId][_jobId]) {
            devBlock[_jobId] = _blockId;
            delete jobPushRequest[_blockId][_jobId];
        } else {
            if (
                collectiveJobFunding[_jobId] || 
                !collectiveJobFunding[_jobId] && userContributionToJobTreasury[_jobId][msg.sender] == 0
            ) {
                jobPullRequest[_blockId][_jobId] = true;
            } else {
                devBlock[_jobId] = _blockId;
            }
        }
        emit AcceptedJobPushRequestOrPulledRequest(_blockId, _jobId);
    }

    function acceptJobPullRequestOrPushRequest(
        uint256 _blockId,
        uint256 _jobId
    ) external {
        require(
            jobMaster[_jobId] == msg.sender && !collectiveJobFunding[_jobId], 
            "acceptJobPullRequestOrPushRequest: not a contributor"
        );
        require(
            jobStatus[_jobId] != JobStatus.INACTIVE, 
            "acceptJobPullRequestOrPushRequest: not an active job"
        );
        if (jobPullRequest[_blockId][_jobId]) {
            devBlock[_jobId] = _blockId;
            delete jobPullRequest[_blockId][_jobId];
        } else if (
            collectiveJobFunding[_jobId] || 
            !collectiveJobFunding[_jobId] && userContributionToJobTreasury[_jobId][msg.sender] == 0
        ) {
            jobPushRequest[_blockId][_jobId] = true;
        } else {
            devBlock[_jobId] = _blockId;
        }
        emit AcceptedJobPullRequestOrPushedRequest(_blockId, _jobId);
    }

    function voteAcceptJobPullRequestOrPushRequest(
        uint256 _blockId,
        uint256 _jobId
    ) external {
        require(
            balanceOf(msg.sender, _jobId) > 0, 
            "voteAcceptJobPullRequestOrPushRequest: not a contributor"
        );
        require(
            jobStatus[_jobId] != JobStatus.INACTIVE, 
            "voteAcceptJobPullRequestOrPushRequest: not an active job"
        );
        updateUserTokenShare(_jobId, msg.sender);
        votesTotalJobPullRequestOrPushRequest[_jobId][_blockId] += balanceOf(msg.sender, _jobId);
        if (votesTotalJobPullRequestOrPushRequest[_jobId][_blockId] * 1000 > minJobPullRequestOrPushRequestQuorum * totalSupply[_jobId]) {
            if (jobPullRequest[_blockId][_jobId]) {
                devBlock[_jobId] = _blockId;
                delete jobPullRequest[_blockId][_jobId];
            } else if (
                collectiveJobFunding[_jobId] || 
                !collectiveJobFunding[_jobId] && userContributionToJobTreasury[_jobId][msg.sender] == 0
            ) {
                jobPushRequest[_blockId][_jobId] = true;
            } else {
                devBlock[_jobId] = _blockId;
            }
            delete votesTotalJobPullRequestOrPushRequest[_jobId][_blockId];
        }
        emit VotedAcceptJobPullRequestOrPushRequest(_blockId, _jobId);
    }

    function acceptBlockPushRequestOrPullRequest(
        uint256 _blockIdFrom,
        uint256 _blockIdTo
    ) external {
        require(
            msg.sender == rootBlockOwner[_blockIdFrom] && 
            blockUpdateIndex[_blockIdFrom] == chainUpdateIndex[chainNumber[_blockIdFrom]], 
            "acceptBlockPushRequestOrPullRequest: not the root block owner"
        );
        if (blockPushRequest[_blockIdTo][_blockIdFrom]) {
            headBlock[_blockIdTo] = _blockIdFrom;
            outChained[_blockIdTo] = true;
            delete blockPushRequest[_blockIdTo][_blockIdFrom];
            chainNumber[_blockIdTo] = chainNumber[_blockIdFrom];
            chainUpdateIndex[chainNumber[_blockIdFrom]]++;
        } else {
            if (
                rootBlockOwner[_blockIdTo] == msg.sender && 
                blockUpdateIndex[_blockIdTo] == chainUpdateIndex[chainNumber[_blockIdTo]]
            ) {
                headBlock[_blockIdTo] = _blockIdFrom;
                delete outChained[_blockIdTo];
            } else {
                blockPullRequest[_blockIdFrom][_blockIdTo] = true;
            }
        }
        emit AcceptedBlockPushRequestOrPullRequest(_blockIdFrom, _blockIdTo);
    }

    function acceptBlockPullRequestOrPushRequest(
        uint256 _blockIdFrom,
        uint256 _blockIdTo
    ) external {
          require(
            jobStatus[_jobId] != JobStatus.INACTIVE, 
            "acceptBlockPullRequestOrPushRequest: not an active job"
        );
        require(
            msg.sender == rootBlockOwner[_blockIdFrom] && 
            blockUpdateIndex[_blockIdFrom] == chainUpdateIndex[chainNumber[_blockIdFrom]], 
            "acceptBlockPullRequestOrPushRequest: not the root block owner"
        );
        if (blockPullRequest[_blockIdTo][_blockIdFrom]) {
            headBlock[_blockIdFrom] = _blockIdTo;
            outChained[_blockIdFrom] = true;
            delete blockPullRequest[_blockIdTo][_blockIdFrom];
            chainNumber[_blockIdFrom] = chainNumber[_blockIdTo];
            chainUpdateIndex[chainNumber[_blockIdFrom]]++;
        } else {
            if (rootBlockOwner[_blockIdTo] == msg.sender && 
                blockUpdateIndex[_blockIdTo] == chainUpdateIndex[chainNumber[_blockIdTo]]
            ) {
                headBlock[_blockIdFrom] = _blockIdTo;
                delete outChained[_blockIdFrom];
            } else {
                blockPushRequest[_blockIdFrom][_blockIdTo] = true;
            }
        }
        emit AcceptedBlockPullRequestOrPushRequest(_blockId, _jobId);
    }

    function updateRootBlockOwner(
        uint256 _blockId
    ) external {
        if (outChained[_blockId]) {
            require(
                msg.sender == rootBlockOwner[_blockId], 
                "updateRootBlockOwner: not the root block owner"
            );
        } else if (headBlock[_blockId] != 0) {
            require(
                msg.sender == rootBlockOwner[headBlock[_blockId]], 
                "updateRootBlockOwner: not the root block owner"
            );
            require(
                blockUpdateIndex[headBlock[_blockId]] == chainUpdateIndex[chainNumber[headBlock[_blockId]]], 
                "updateRootBlockOwner: not updated root block owner"
            );
            chainNumber[_blockId] = chainNumber[headBlock[_blockId]];
            if (rootBlockOwner[_blockId] != msg.sender) {
                previousRootBlockOwner[_blockId] = rootBlockOwner[_blockId];
                rootBlockOwner[_blockId] = msg.sender;
            }
        }
        blockUpdateIndex[_blockId] = chainUpdateIndex[chainNumber[_blockId]];
        emit UpdatedRootBlockOwner(_blockId);
    }

    function batchUpdateRootBlockOwner(
        uint256[] _blockId
    ) external {
        for (uint i = 0; i < _blockId.length; i++) {
            updateRootBlockOwner(_blockId[i]);
        }
    }

    function updateBlockOwnerPrice(
        uint256 _blockId,
        uint256 _new
    ) external {
        require(
            blockUpdateIndex[_blockId] == chainUpdateIndex[chainNumber[_blockId]] && 
            msg.sender == rootBlockOwner[_blockId], 
            "updateRootBlockOwnerPrice: not the root block owner"
        );
        require(
            headBlock[_blockId] != 0 &&
            rootBlockOwner[headBlock[_blockId]] == msg.sender, 
            "updateRootBlockOwnerPrice: the block is not the headblock"
        );
        blockOwnerPrice[_blockId] = _new;
        emit UpdatedBlockOwnerPrice(_blockId, _new);
    }

    function updateCollectiveJobOwnerPrice(
        uint256 _jobId,
        uint256 _new
    ) external {
        require(
            balanceOf(msg.sender, _jobId) > 0, 
            "updateCollectiveJobOwnerPrice: sender not an owner of the asset"
        );
        require(
            jobStatus[_jobId] == JobStatus.FINALIZED, 
            "updateCollectiveJobOwnerPrice: auction live cannot update price"
        );
        uint256 old = ownerPrices[_jobId][msg.sender];
        require(
            _new != old, 
            "updateCollectiveJobOwnerPrice: not an update"
        );
        uint256 weight = balanceOf(msg.sender, _jobId);

        if (votingTokens == 0) {
            votingTokens[_jobId] = weight;
            reserveTotal[_jobId] = weight * _new;
        }
        // they are the only one voting
        else if (weight == votingTokens && old != 0) {
            reserveTotal[_jobId] = weight * _new;
        }
        // previously they were not voting
        else if (old == 0) {
            uint256 averageReserve = reserveTotal / votingTokens;
            uint256 reservePriceMin = averageReserve * minReserveFactor / 1000;
            require(
                _new >= reservePriceMin, 
                "updateCollectiveJobOwnerPrice: reserve price too low"
            );
            uint256 reservePriceMax = averageReserve * maxReserveFactor / 1000;
            require(
                _new <= reservePriceMax, 
                "updateCollectiveJobOwnerPrice: reserve price too high"
            );
            votingTokens[_jobId] += weight;
            reserveTotal[_jobId] += weight * _new;
        }
        // they no longer want to vote
        else if (_new == 0) {
            votingTokens[_jobId] -= weight;
            reserveTotal[_jobId] -= weight * old;
        }
        // they are updating their vote
        else {
            uint256 averageReserve = (reserveTotal[_jobId] - (old * weight)) / (votingTokens[_jobId] - weight);
            uint256 reservePriceMin = averageReserve * minReserveFactor / 1000;
            require(
                _new >= reservePriceMin, 
                "updateCollectiveJobOwnerPrice: reserve price too low"
            );
            uint256 reservePriceMax = averageReserve * maxReserveFactor / 1000;
            require(
                _new <= reservePriceMax, 
                "updateCollectiveJobOwnerPrice: reserve price too high"
            );
            reserveTotal[_jobId] = reserveTotal[_jobId] + (weight * _new) - (weight * old);
        }
        ownerPrices[_jobId][msg.sender] = _new;
        emit UpdatedCollectiveJobOwnerPrice(msg.sender, _new);
    }

    

    function workerPaymentFunction(
        uint256 _jobId,
        uint256 _amount
    ) internal {
        require(
            jobStatus[_jobId] == JobStatus.WORKING, 
            "workerPaymentFunction: no work ongoing"
        );
        require(
            _amount >= jobTreasury[_jobId], 
            "workerPaymentFunction: not enough funds"
        );
        unstakingFunction(jobFundingToken[_jobId], devGaangsProtocolAddress, _amount * (devGaangsShare / 1000));
        if (appointedDev[_jobId] != address(0)) {
            unstakingFunction(jobFundingToken[_jobId], appointedDev[_jobId], _amount * (1 - devGaangsShare / 1000));
        } else {
            gaangTreasury[appointedGaang[_jobId]][jobFundingToken[_jobId]] += _amount * (devGaangsShare / 1000);
        }
        emit PaidWorker(_jobId, jobFundingToken[_jobId], _amount);
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
        address _transferTo,
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
            ERC20lib.transferFrom(_tokenAddressToStakeTo, address(this), _transferTo, _amount);
        } 
    }

    function updateUserTokenShare(
        uint256 _jobId,
        address _user
    ) public {
        require(
            collectiveJobFunding[_jobId], 
            "updateUserTokenShare: must be an active job funding"
        );
        require(
            jobStatus[_jobId] == JobStatus.WORKING ||
            jobStatus[_jobId] == JobStatus.FINALIZED ||
            jobStatus[_jobId] == JobStatus.CHALLENGED ||
            jobStatus[_jobId] == JobStatus.SETTLEDCHALLENGE, 
            "updateUserContributionBalance: not appointed job funding"
        );
        if (appointedDev[_jobId] != address(0) && bidOnDev[_jobId][_user][appointedDev[_jobId]] > 0) {
            userContributionToJobTreasury[_jobId][_user] += bidOnDev[_jobId][_user][appointedDev[_jobId]];
            if (collectiveJobFunding[_jobId]) {
                _mint(_user, jobId, 1000 * bidOnDev[_jobId][_user][appointedDev[_jobId]], "");
            }
        } else if (appointedGaang[_jobId] != 0 && bidOnGaang[_jobId][_user][appointedGaang[_jobId]] > 0) {
            userContributionToJobTreasury[_jobId][_user] += bidOnGaang[_jobId][_user][appointedGaang[_jobId]];
            if (collectiveJobFunding[_jobId]) {
                _mint(_user, jobId, 1000 * bidOnGaang[_jobId][_user][appointedGaang[_jobId]], "");
            }
        }
    }
}
    
WrappedMaticInterface(wrappedMaticContract).deposit{value: _value}();
WrappedMaticInterface(wrappedMaticContract).transfer(_to, _value);