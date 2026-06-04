## Lab Objective

This project demystifies container networking by manually constructing isolated environments from the ground up using native Linux kernel **Namespaces**.

By rebuilding these network stacks, this lab serves as a hands-on verification of how container runtimes (like Docker/Kubernetes) abstract OS-level network primitives. It provides a clear view into the underlying mechanisms that govern network isolation, connectivity, and routing in modern containerized environments.

## Steps & Implementation

1. Environment Isolation (Namespaces)
   **Objective:** Achieve resource isolation by creating independent namespaces.
2. Point-to-Point Communication (veth pairs)
   **Objective**: Establish connectivity between isolated network namespaces.
   **Key Actions:**
   Implemented `veth pairs` to bridge two isolated network namespaces.
   Configured IP addresses and interface states (`up`) to enable direct traffic between the `client-ns` and `server-ns`.
3. Network Topology Scaling (Bridge)
   **Objective:** Manage multiple namespaces efficiently using a virtual bridge.
   **Key Actions:**
   Created a virtual bridge (`br0`) to connect multiple namespaces.
   Configured routing and SNAT (using `iptables`) to allow namespaces to communicate with the host and the external internet.
```mermaid
flowchart TD
	EX[google]
	H0[br0 also router <br/> 172.18.0.1/24 <br/> default GW <br/> ORB Host]
	n1[ns1 <br/> 172.18.0.17/28]
	n2[ns2 <br/> 172.18.0.18/28]
	n3[ns3 <br/> 172.18.0.55/28]
	
	n1 & n2 & n3 <---> |veth connect to bridge| H0 
	H0 <--->|SNAT| EX
	
```
4. DNAT 
	Isolate bridge and host, use DNAT to send request from host to ns1/2/3
	`[172.18.0.1/24 <br/> default GW]`
```mermaid
	flowchart LR
		EX[google]
		H0[ORB Host]
		R0[Router NS]
		n1[ns1 <br/> 172.18.0.17/28]
		n2[ns2 <br/> 172.18.0.18/28]
		br[Br0]
		
		subgraph R0
			br
			end
			
		n1 & n2 <---> |veth| br
		H0 --->|DNAT| R0
		H0 <---> EX
```
4. Firewall filtering
	 

