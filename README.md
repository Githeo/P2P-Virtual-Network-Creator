# P2P-Virtual-Network-Creator
Create a virtual network with Linux namespace facilities for P2P experiments

This script creates a virtual network with Linux namespace facilities.
A number of Client namespaces are created as long as a Server namespace.
Clients have 2 interfaces:
 - eth1: to comunicate in a P2P fashion among them. The other side of 
         the virtual link is called brp2p-cX (where X is the client number)
         and it is connected to a virtual bridge for the P2P communication
         called 'virbr1'. eth1 has the IP addr. 10.1.1.X/24
 - eth0: to communicate to the Server. Its IP addr. is 10.1.2.X/24
         The other side of the virtual link is called 'brcs-cX' and
         is connected to a new virtual bridge called 'virbr0' 
         for the Client-Server communication
The Server has only one interface eth0, IP addr. 10.1.2.(n+1)/24
where n is the total number of clients. This interface is connected
to the interface 'brcs-server' of the virbr0 bridge

PARAMETERS: 1 - number of virtual clients
