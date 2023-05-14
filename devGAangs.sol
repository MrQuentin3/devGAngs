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
        if (msg.sender == rootBlockOwner[_addToBlock]) {
            headBlock[jobId] = _addToBlock;
        } else {
            requestedAddBlock[_addToBlock][jobId] = true;
        }
        _mint(msg.sender, jobId, 1000 * contribution, "");
        collectiveJobFunding[jobId] = true;
        fundingDeadline[jobId] = block.timestamp + numberFundingDays * 1 days;
        jobManager[jobId] = msg.sender;
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
            jobManager[_jobId] == msg.sender, 
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
            userContributionToJobTreasury[_jobId][msg.sender] > 0 && !collectiveJobFunding[_jobId], 
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
            userContributionToJobTreasury[_jobId][msg.sender] > 0, 
            "voteToCancelFundingNewJob: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.FUNDING && block.timestamp > numberCancelDays * 1 days + fundingDeadline[_jobId] ||
            jobStatus[_jobId] == JobStatus.APPOINTING, 
            "voteToCancelFundingNewJob: cancelling not allowed"
        );
        votesTotalCancel[_jobId] += balanceOf(msg.sender, _jobId);
        if (votesTotalCancel[_jobId] * 1000 > minCancelQuorum * totalSupply[_jobId]) {
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
            userContributionToJobTreasury[_jobId][msg.sender] > 0, 
            "voteToChangeJobMaster: not a contributor"
        );
        require(
            userContributionToJobTreasury[_jobId][_proposedMaster] > 0, 
            "voteToChangeJobMaster: not a contributor"
        );
        require(
            jobStatus[_jobId] != JobStatus.INACTIVE && 
            jobStatus[_jobId] != JobStatus.CANCELLED, 
            "voteToChangeJobMaster: cancelling not allowed"
        );
        votesTotalMaster[_jobId][_proposedMaster] += balanceOf(msg.sender, _jobId);
        if (votesTotalMaster[_jobId][_proposedMaster] * 1000 > minMasterQuorum * totalSupply(_jobId)) {
            jobMaster[_jobId] = _proposedMaster;
        }
        emit VotedToCancelFundingNewJob(_jobId, msg.sender, _proposedMaster);
    }

    function withdrawUserContribution(
        uint256 _jobId
    ) public {
        uint256 contribution;
        if (!collectiveJobFunding[_jobId]) {
            contribution = userContributionToJobTreasury[_jobId][msg.sender];
        } else {
            contribution = balanceOf(msg.sender, _jobId);
        }
        require(
            contribution > 0 && !claimed[_jobId][msg.sender], 
            "withdrawUserContribution: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.CANCELLED || jobStatus[_jobId] == JobStatus.SUCCESSFULEMPLOYERCHALLENGE, 
            "withdrawUserContribution: job funding still active"
        );
        if (jobStatus[_jobId] == JobStatus.SUCCESSFULEMPLOYERCHALLENGE && collectiveJobFunding[_jobId]) {
            contribution = (contribution / totalSupply(_jobId)) * (arbitrageCompensation[_jobId] / 1000) * jobTreasury[_jobId];
        }
        unstakingFunction(jobFundingToken[_jobId], msg.sender, contribution);
        claimed[_jobId][msg.sender] = true;
        emit WithdrawnUserContribution(_jobId, msg.sender, contribution);
    }

    function proposeNewJob(
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
        if (msg.sender == rootBlockOwner[_addToBlock]) {
            headBlock[jobId] = _addToBlock;
        } else {
            requestedAddBlock[_addToBlock][jobId] = true;
        }
        _mint(msg.sender, jobId, 1000 * contribution, "");
        jobManager[jobId] = msg.sender;
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
        address[] _appointedDev
    ) external payable {
        require(
            _addToBlock.length == _rewardAmount.length == _amount.length == _apppointedGaang.length == _tokenAddress.length == _appointedDev.length, 
            "batchProposeNewJob: wrong parameters length"
        );
        for (uint i = 0; i < _rewardAmount.length; i++) {
            if (_rewardAmount[i] > 0) {
                proposeFundingNewJob(_addToBlock[i], _rewardAmount[i], _amount[i], _tokenAddress[i], _apppointedGaang[i], _appointedDev[i]);
            } else {
                proposeNewJob(_addToBlock[i], _amount[i], _apppointedGaang[i], _tokenAddress[i], _appointedDev[i]);
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
            userContributionToJobTreasury[_jobId][msg.sender] > 0 && !collectiveJobFunding[_jobId], 
            "appointDevOrGaang: not a contributor"
        );
        if (_appointedDev != address(0) && devProposal[_jobId][_appointedDev] > 0) {
            if (devProposal[_jobId][_appointedDev] > jobTreasury[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = devProposal[_jobId][_appointedDev];
                contributeFundingNewJob(_jobId, jobRewardAmount[_jobId]);
            } else if (devProposal[_jobId][_appointedDev] == jobTreasury[_jobId] + totalBidOnDev[_jobId][_appointedDev]) {
                jobTreasury[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
            }
            appointedDev[_jobId] = _appointedDev;
        } else if (_apppointedGaang != 0 && gaangProposal[_jobId][_apppointedGaang] > 0) {
            if (gaangProposal[_jobId][_apppointedGaang] > jobTreasury[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
                jobRewardAmount[_jobId] = gaangProposal[_jobId][_apppointedGaang];
                contributeFundingNewJob(_jobId, jobRewardAmount[_jobId]);
            } else if (gaangProposal[_jobId][_apppointedGaang] == jobTreasury[_jobId] + totalBidOnGaang[_jobId][_apppointedGaang]) {
                jobTreasury[_jobId] += totalBidOnGaang[_jobId][_apppointedGaang];
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
            balanceOf(msg.sender, _jobId) > 0, 
            "voteToAppointDevOrGaang: not a contributor"
        );
        require(
            jobStatus[_jobId] == JobStatus.APPOINTING, 
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
                }
                appointedDev[_jobId] = _appointedDev;
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
        uint256 _gaangNumber,
        uint256 _askedRewardAmount,
        uint256 _goodwillAmount,
        uint256 _addToBlock
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
        if (msg.sender == rootBlockOwner[_addToBlock]) {
            headBlock[_jobId] = _addToBlock;
        } else {
            requestedAddBlock[_addToBlock][_jobId] = true;
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
            userContributionToJobTreasury[_jobId][msg.sender] > 0 && !collectiveJobFunding[_jobId], 
            "payWorker: not a contributor"
        );
        if (_amount >= jobTreasury[_jobId]) {
            jobStatus[_jobId] = JobStatus.EXTRAFUNDING;
            jobRewardAmount[_jobId] = _amount;
            fundingDeadline[_jobId] = block.timestamp + numberFundingDays * 1 days;
            contributeFundingNewJob(_jobId, jobFundingToken[_jobId], jobRewardAmount[_jobId]);
        }
        workerPaymentFunction(_jobId, _amount);
        emit PaidWorker(_jobId, jobFundingToken[_jobId], _amount);
    }

    function voteToPayWorker(
        uint256 _jobId,
        uint256 _amount
    ) {

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
        updateUserContributionBalance(_jobId, msg.sender);
        if (appointedDev[_jobId] != address(0)) {
            unstakingFunction(jobFundingToken[_jobId], appointedDev[_jobId], _amount);
        } else {
            gaangTreasury[appointedGaang[_jobId]][jobFundingToken[_jobId]] += _amount;
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

    function updateUserContributionBalance(
        uint256 _jobId,
        address _user
    ) internal {
        if (!userUpdatedBalance[_user]) {
            if (appointedDev[_jobId] != address(0) && bidOnDev[_jobId][_user][appointedDev[_jobId]] > 0) {
                userContributionToJobTreasury[_jobId][_user] += bidOnDev[_jobId][_user][appointedDev[_jobId]];
                if (collectiveJobFunding[_jobId]) {
                    _mint(msg.sender, jobId, 1000 * bidOnDev[_jobId][_user][appointedDev[_jobId]], "");
                }
            } else if (appointedGaang[_jobId] != 0 && bidOnGaang[_jobId][_user][appointedGaang[_jobId]] > 0) {
                userContributionToJobTreasury[_jobId][_user] += bidOnGaang[_jobId][_user][appointedGaang[_jobId]];
                if (collectiveJobFunding[_jobId]) {
                    _mint(msg.sender, jobId, 1000 * bidOnGaang[_jobId][_user][appointedGaang[_jobId]], "");
                }
            }
            userUpdatedBalance[_user] = true;
        }
    }
}
    
WrappedMaticInterface(wrappedMaticContract).deposit{value: _value}();
WrappedMaticInterface(wrappedMaticContract).transfer(_to, _value);