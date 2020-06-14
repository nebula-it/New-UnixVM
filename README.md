# New-UnixVM
Powershell function to create new Unix VM from a template in **Hyper-V**. This function copies the VHD of an existing template VM and provisions the new VM using cloud-init.

# Pre-requisities 
1. Create a template Linux VM with cloud-init installed. By default this function tries to find template VM named "Template-CentOS8" but you can change that in parameters.
2. Make sure you have OSCDIMG installed on your hypervisor. ADK can be downloaded from [here](https://www.microsoft.com/en-us/download/confirmation.aspx?id=39982). You only need to install deployment tool.
3. Add your SSH key to [Line 255](https://github.com/nebula-it/New-UnixVM/blob/51b7052a3455d72976fbbc9a1ff26c0e93d8d8da/New-UnixVM.psm1#L255). Or if you are comfortable feel free to edit cloud-init config as per your needs.

# Limitations
1. Cloud-init config is very basic. It is used to do the bare minimum to power up the VM, the idea is that once the VM is online Ansible will take over to complete rest of the tasks
2. The disk parition inside new Linux VM is not expanded so the size will be same as template VM and you will need to manully expand the partition and file syste. Similarly, secondary VHD is not initialized at all just attached to the VM. I am currently working on Ansible playbook to handle these tasks, which are in very early stages. (I just started to learn Ansible)
3. This was only tested with CentOS8 Server. Since cloud-init same across other distros I am pretty sure it will just work.
4. On the hypervisor side it was only tested with Windows Server 2016 And Windows Server 2019, but it should work fine with Windows Server 2012 as long as it has Powershell 5 installed.

# Next Steps
1. I will see how well this function servers in its current form and will be making adjustments improvements as needed
2. Once the function is matured I'll add it to powershell gallery.

# Improvements/Feedback
I'm always happy to hear any feedback so if you have any ideas for improvement or face any issues feel free to open an issue. Contributions are welcome.
