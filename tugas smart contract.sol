// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SecureLancer {
    
    enum JobStatus { Funded, InProgress, AwaitingApproval, Completed, Refunded }
    
    struct Job {
        address client;
        address payable freelancer;
        uint256 amount;
        uint256 deadline;
        JobStatus status;
    }
    
    mapping(uint256 => Job) public jobs;
    uint256 public jobCount;

    event JobCreated(uint256 jobId, address client, uint256 amount, uint256 deadline);
    event JobAccepted(uint256 jobId, address freelancer);
    event WorkSubmitted(uint256 jobId);
    event FundsReleased(uint256 jobId, address freelancer, uint256 amount);
    event FundsRefunded(uint256 jobId, address client, uint256 amount);

    function createJob(uint256 _durationInSeconds) public payable {
        require(msg.value > 0, "Deposit harus > 0");
        jobCount++;
        jobs[jobCount] = Job(
            msg.sender, 
            payable(address(0)), 
            msg.value, 
            block.timestamp + _durationInSeconds, 
            JobStatus.Funded
        );
        emit JobCreated(jobCount, msg.sender, msg.value, jobs[jobCount].deadline);
    }

    function acceptJob(uint256 _jobId) public {
        Job storage job = jobs[_jobId];
        require(job.status == JobStatus.Funded, "Proyek belum siap");
        require(msg.sender != job.client, "Client tidak bisa jadi freelancer");
        
        job.freelancer = payable(msg.sender);
        job.status = JobStatus.InProgress;
        emit JobAccepted(_jobId, msg.sender);
    }

    function submitWork(uint256 _jobId) public {
        Job storage job = jobs[_jobId];
        require(job.status == JobStatus.InProgress, "Belum in progress");
        require(msg.sender == job.freelancer, "Hanya freelancer");
        
        job.status = JobStatus.AwaitingApproval;
        emit WorkSubmitted(_jobId);
    }

    function releaseFunds(uint256 _jobId) public {
        Job storage job = jobs[_jobId];
        require(job.status == JobStatus.AwaitingApproval, "Belum disubmit");

        // VULN-1: SC01 Access Control
        // require(msg.sender == job.client, "Hanya client"); 

        job.status = JobStatus.Completed;
        
        (bool success, ) = job.freelancer.call{value: job.amount}("");
        require(success, "Transfer ke freelancer gagal");
        
        emit FundsReleased(_jobId, job.freelancer, job.amount);
    }

    function refund(uint256 _jobId) public {
        Job storage job = jobs[_jobId];
        require(msg.sender == job.client, "Hanya client");
        require(job.status != JobStatus.Completed, "Sudah cair");
        require(block.timestamp > job.deadline, "Belum deadline");
        require(job.amount > 0, "Saldo kosong");

        uint256 amountToRefund = job.amount;

        // VULN-2: SC05 Reentrancy Attacks
        // Mentransfer dana terlebih dahulu sebelum memperbarui state (status & amount)
        (bool success, ) = msg.sender.call{value: amountToRefund}("");
        require(success, "Transfer gagal");

        job.status = JobStatus.Refunded;
        job.amount = 0;
        
        emit FundsRefunded(_jobId, msg.sender, amountToRefund);
    }
}
