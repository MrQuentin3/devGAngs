// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

/*
devGaangs v1.0
Quentin for FrAaction Gangs
*/

contract devGaangs {

    function proposeFundingNewJob(
        uint256 _rewardAmount,
        uint256 _transferedWmaticOrGhst,
        bool _inWmatic
    ) public payable {
        jobId++;
        uint256 contribution;
        if (msg.value > 0) {
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            contribution = msg.value;
            jobFundingInWmatic[jobId] = true;
        } if (_transferedWmaticOrGhst > 0) {
            if (_inWmatic) {
                jobFundingInMatic[jobId] = true;
                WrappedMaticInterface(wrappedMaticContract).transferFrom(msg.sender, address(this), _transferedWmaticOrGhst);
            } else {
                ERC20lib.transferFrom(ghstContract, msg.sender, address(this), _transferedWmaticOrGhst);
            }
            contribution = _transferedWmaticOrGhst;
        } else { 
            return;
        }
        if (jobRewardAmount[jobId] > contribution) {
            fundingJob[jobId] = true;
        }
        collectiveJobFunding[jobId] = true;
        activeJob[jobId] = true;
        fundingDeadline[jobId] = block.timestamp + numberFundingDays * 1 days;
        jobInitiator[jobId] = msg.sender;
        contributedToJobReward[jobId] += contribution;
        userContributionToJobReward[jobId][msg.sender] += contribution;
        jobRewardAmount[jobId] = _rewardAmount;
        emit ProposedFundingNewJob(jobId, _rewardAmount, contribution);
    }

    function contributeFundingNewJob(
        uint256 _jobId,
        uint256 _transferedWmaticOrGhst
    ) public payable {
        require(
            block.timestamp <= fundingDeadline[_jobId], 
            "contributeFundingNewJob: funding deadline expired"
        );
        uint256 contribution;
        if (msg.value > 0 && jobFundingInWmatic[_jobId]) {
                require(
                block.timestamp <= fundingDeadline[_jobId], 
                "contributeFundingNewJob: funding deadline expired"
            );
            WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
            contribution = msg.value;
        } if (_transferedWmaticOrGhst > 0) {
            if (jobFundingInWmatic[_jobId]) {
                WrappedMaticInterface(wrappedMaticContract).transferFrom(msg.sender, address(this), _transferedWmaticOrGhst);
            } else {
                ERC20lib.transferFrom(ghstContract, msg.sender, address(this), _transferedWmaticOrGhst);
            }
            contribution = _transferedWmaticOrGhst;
        } else { 
            return;
        }
        contributedToJobReward[_jobId] += contribution;
        userContributionToJobReward[_jobId][msg.sender] += contribution;
        if (contributedToJobReward[_jobId] >= jobRewardAmount[_jobId]) fundingJob[_jobId] = false;
        emit ContributedFundingNewJob(_jobId, contribution);
    }

    function updateFundingNewJob(
        uint256 _jobId,
        uint256 _updatedReward
    ) public {
        require(
            block.timestamp <= fundingDeadline[_jobId], 
            "updateFundingNewJob: funding deadline expired"
        );
        require(
            fundingJob[_jobId], 
            "updateFundingNewJob: must be active job funding"
        );
        require(
            jobInitiator[_jobId] == msg.sender, 
            "updateFundingNewJob: must be the job initiator"
        );
        require(
            _updatedReward >= contributedToJobReward[_jobId], 
            "updateFundingNewJob: must be greater than already collected funds for the job reward"
        );
        if (_updatedReward <= contributedToJobReward[_jobId]) fundingJob[_jobId] = false;
        emit UpdatedFundingNewJob(_jobId, _updatedReward);
    }

    function voteToCancelFundingNewJob(
        uint256 _jobId
    ) public {
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0, 
            "voteToCancelFundingNewJob: not a contributor"
        );
        require(
            votesTotalApprove * 1000 <= minApproveQuorum * contributedToJobReward[_jobId], 
            "voteToCancelFundingNewJob: already appointed worker or GAang"
        );
        require(
            block.timestamp > numberCancelDays * 1 days + fundingDeadline[_jobId], 
            "voteToCancelFundingNewJob: cancel deadline not expired"
        );
        votesTotalCancel += userContributionToJobReward[_jobId][msg.sender];
        if (votesTotalCancel * 1000 > minCancelQuorum * contributedToJobReward[_jobId]) {
            activeJob[_jobId] = false;
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
            !activeJob[_jobId] && votesTotalCancel * 1000 > minCancelQuorum * contributedToJobReward[_jobId], 
            "withdrawUserContribution: job funding still active"
        );
        if (jobFundingInWmatic[_jobId]) {
            WrappedMaticInterface(wrappedMaticContract).transferFrom(address(this), msg.sender, contribution);
        } else {
            ERC20lib.transferFrom(ghstContract, address(this), msg.sender, contribution);
        }
        delete userContributionToJobReward[_jobId][msg.sender];
        emit WithdrawnUserContribution(_jobId, msg.sender, contribution);
    }

    function proposeNewJob(
        uint256 _jobId,
        uint256 _rewardAmount,
        uint256 _transferedWmaticOrGhst,
        bool _inWmatic,
        address _appointedWorkerOrGaang
    ) public payable {
        if (activeJob[_jobId] && collectiveJobFunding[jobId]) {
            require(
                jobInitiator[_jobId] == msg.sender, 
                "proposeNewJob: must be the job initiator"
            );
            if (contributedToJobReward[_jobId] >= jobRewardAmount[_jobId]) fundingJob[_jobId] = false;
            require(
                !fundingJob[_jobId], 
                "proposeNewJob: must be active job funding"
            );
            appointedWorker[_jobId] = _appointedWorkerOrGaang;
            if (votesTotalApprove > 0) delete votesTotalApprove;
        } else {
            jobId++;
            uint256 contribution;
            if (msg.value > 0) {
                WrappedMaticInterface(wrappedMaticContract).deposit{value: msg.value}();
                contribution = msg.value;
                jobFundingInWmatic[jobId] = true;
            } if (_transferedWmaticOrGhst > 0) {
                if (_inWmatic) {
                    jobFundingInMatic[jobId] = true;
                    WrappedMaticInterface(wrappedMaticContract).transferFrom(msg.sender, address(this), _transferedWmaticOrGhst);
                } else {
                    ERC20lib.transferFrom(ghstContract, msg.sender, address(this), _transferedWmaticOrGhst);
                }
                contribution = _transferedWmaticOrGhst;
            } else { 
                return;
            }
            if (jobRewardAmount[jobId] > contribution) {
                fundingJob[jobId] = true;
            }
            activeJob[jobId] = true;
            jobInitiator[jobId] = msg.sender;
            appointedWorker[jobId] = _appointedWorkerOrGaang;
            contributedToJobReward[jobId] += contribution;
            userContributionToJobReward[jobId][msg.sender] += contribution;
            jobRewardAmount[jobId] = _rewardAmount;
        }

    }
    
    function voteToApproveAppointedWorkerOrGaang(
        uint256 _jobId
    ) public {
        require(
            userContributionToJobReward[_jobId][msg.sender] > 0, 
            "voteToApproveAppointedWorkerOrGaang: not a contributor"
        );
        require(
            !fundingJob[_jobId], 
            "voteToApproveAppointedWorkerOrGaang: job funding still active"
        );
        require(
            appointedWorker[_jobId] != address(0), 
            "voteToApproveAppointedWorkerOrGaang: no appointed worker or GAang"
        );
        votesTotalApprove += userContributionToJobReward[_jobId][msg.sender];
        if (votesTotalApprove * 1000 > minApproveQuorum * contributedToJobReward[_jobId]) {
            
        } 
        emit VotedToApproveAppointedWorkerOrGaang(_jobId, msg.sender);
    }
}
    
WrappedMaticInterface(wrappedMaticContract).deposit{value: _value}();
WrappedMaticInterface(wrappedMaticContract).transfer(_to, _value);